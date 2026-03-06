package com.pushup.domain.usecase.sync

import com.pushup.data.api.ApiException
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.UpdateTimeCreditRequest
import com.pushup.data.api.isTransient
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.repository.TimeCreditRepository
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay

/**
 * Use-case: Synchronise the local [TimeCredit] record for a user with Supabase.
 *
 * ## Offline-First strategy
 * Credit mutations (earn / spend) are always applied locally first with
 * [SyncStatus.PENDING]. This use-case pushes those pending changes to the cloud
 * when a network connection is available.
 *
 * ## Conflict resolution -- "Last Write Wins"
 * The [TimeCredit.lastUpdatedAt] timestamp is used as the conflict arbiter:
 * - If the local record is **strictly newer** than the remote record -> PATCH remote.
 * - If the remote record is newer or equal -> discard local change, update local
 *   from remote, and mark as [SyncStatus.SYNCED].
 *
 * ## Retry with exponential back-off
 * Transient errors are retried up to [maxRetries] times with exponential
 * back-off: `baseDelayMs * 2^attempt` (default: 500ms, 1s, 2s).
 *
 * @property timeCreditRepository  Local repository for reading and updating credits.
 * @property supabaseClient        Remote API client for Supabase PostgREST operations.
 * @property networkMonitor        Checks whether the device has internet connectivity.
 * @property maxRetries            Maximum retry attempts (default 3).
 * @property baseDelayMs           Base delay in milliseconds for exponential back-off (default 500).
 */
class SyncTimeCreditUseCase(
    private val timeCreditRepository: TimeCreditRepository,
    private val supabaseClient: CloudSyncApi,
    private val networkMonitor: NetworkMonitor,
    private val maxRetries: Int = 3,
    private val baseDelayMs: Long = 500L,
) {

    /**
     * Syncs the [TimeCredit] record for [userId] to Supabase.
     *
     * If the local record has [SyncStatus.SYNCED], this is a no-op.
     * Records with [SyncStatus.PENDING] or [SyncStatus.FAILED] are both eligible.
     *
     * @param userId The ID of the user whose credits to sync.
     * @return A [SyncTimeCreditResult] describing the outcome.
     * @throws IllegalArgumentException if [userId] is blank.
     * @throws SyncException.NoNetwork if the device has no internet connection.
     */
    suspend operator fun invoke(userId: String): SyncTimeCreditResult {
        require(userId.isNotBlank()) { "userId must not be blank" }

        if (!networkMonitor.isConnected()) {
            throw SyncException.NoNetwork("Cannot sync time credit: no internet connection")
        }

        val local = timeCreditRepository.get(userId)
            ?: return SyncTimeCreditResult.NoLocalData

        if (local.syncStatus == SyncStatus.SYNCED) {
            return SyncTimeCreditResult.AlreadySynced
        }

        return syncWithRetry(local)
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    /**
     * [CancellationException] is always re-thrown to preserve structured concurrency.
     */
    private suspend fun syncWithRetry(local: TimeCredit): SyncTimeCreditResult {
        var lastException: Exception? = null

        repeat(maxRetries) { attempt ->
            try {
                return doSync(local)
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiException) {
                if (!e.isTransient) {
                    markFailed(local.userId)
                    return SyncTimeCreditResult.Failed(e)
                }
                lastException = e
                delay(baseDelayMs * (1L shl attempt))
            } catch (e: Exception) {
                lastException = e
                delay(baseDelayMs * (1L shl attempt))
            }
        }

        markFailed(local.userId)
        return SyncTimeCreditResult.Failed(lastException ?: Exception("All retries exhausted"))
    }

    private suspend fun doSync(local: TimeCredit): SyncTimeCreditResult {
        val remote = supabaseClient.getTimeCredit(local.userId)

        return if (remote == null) {
            createRemoteCredit(local)
        } else {
            if (local.lastUpdatedAt > remote.lastUpdatedAt) {
                supabaseClient.updateTimeCredit(
                    userId = local.userId,
                    request = UpdateTimeCreditRequest(
                        totalEarnedSeconds = local.totalEarnedSeconds,
                        totalSpentSeconds = local.totalSpentSeconds,
                    ),
                )
                timeCreditRepository.markAsSynced(local.userId)
                SyncTimeCreditResult.Synced
            } else {
                timeCreditRepository.update(remote)
                SyncTimeCreditResult.PulledFromRemote(remote)
            }
        }
    }

    /**
     * Attempts to create/update the time credit record remotely.
     *
     * Since [CloudSyncApi.updateTimeCredit] uses PATCH (which requires the row to exist),
     * we handle the "no remote row" case by catching [ApiException.NotFound] and
     * marking local as SYNCED optimistically. The row will be created when the
     * backend processes the workout sessions, and the next [SyncFromCloudUseCase]
     * will pull the authoritative state.
     */
    private suspend fun createRemoteCredit(local: TimeCredit): SyncTimeCreditResult {
        return try {
            supabaseClient.updateTimeCredit(
                userId = local.userId,
                request = UpdateTimeCreditRequest(
                    totalEarnedSeconds = local.totalEarnedSeconds,
                    totalSpentSeconds = local.totalSpentSeconds,
                ),
            )
            timeCreditRepository.markAsSynced(local.userId)
            SyncTimeCreditResult.Synced
        } catch (e: ApiException.NotFound) {
            timeCreditRepository.markAsSynced(local.userId)
            SyncTimeCreditResult.Synced
        }
    }

    private suspend fun markFailed(userId: String) {
        try {
            val credit = timeCreditRepository.get(userId) ?: return
            timeCreditRepository.update(credit.copy(syncStatus = SyncStatus.FAILED))
        } catch (_: Exception) {
            // Best-effort.
        }
    }
}

// =============================================================================
// Result type
// =============================================================================

/**
 * Describes the outcome of a [SyncTimeCreditUseCase] invocation.
 */
sealed class SyncTimeCreditResult {

    /** The local record was successfully pushed to Supabase. */
    data object Synced : SyncTimeCreditResult()

    /** The local record was already [SyncStatus.SYNCED] -- nothing to do. */
    data object AlreadySynced : SyncTimeCreditResult()

    /** No local time-credit record exists for this user -- nothing to sync. */
    data object NoLocalData : SyncTimeCreditResult()

    /**
     * The remote record was newer; the local record was updated from the remote.
     *
     * @property remote The authoritative [TimeCredit] pulled from Supabase.
     */
    data class PulledFromRemote(val remote: TimeCredit) : SyncTimeCreditResult()

    /**
     * The sync failed after all retry attempts.
     *
     * @property cause The last exception that caused the failure.
     */
    data class Failed(val cause: Exception) : SyncTimeCreditResult()
}
