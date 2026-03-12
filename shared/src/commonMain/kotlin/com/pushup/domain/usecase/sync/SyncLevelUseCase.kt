package com.pushup.domain.usecase.sync

import com.pushup.data.api.ApiException
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.UpsertUserLevelRequest
import com.pushup.data.api.isTransient
import com.pushup.domain.model.UserLevel
import com.pushup.domain.repository.LevelRepository
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay

/**
 * Use-case: Synchronise the local [UserLevel] (XP) record for a user with Supabase.
 *
 * ## Offline-First strategy
 * XP is always awarded locally first (via [com.pushup.domain.usecase.AwardWorkoutXpUseCase]).
 * This use-case pushes the accumulated local XP to the cloud when a network
 * connection is available, and pulls the authoritative value back if the remote
 * is higher (e.g. XP earned on another device).
 *
 * ## Conflict resolution -- "Highest XP Wins"
 * Unlike timestamps, XP is monotonically increasing and can only go up.
 * The conflict resolution strategy is therefore:
 * - If local [UserLevel.totalXp] > remote totalXp -> upsert remote with local value.
 * - If remote totalXp >= local totalXp -> update local from remote (another device
 *   earned more XP, or the remote is already up to date).
 * - No local record -> pull from remote (new device, restore from cloud).
 * - No remote record -> push local to remote (first sync).
 *
 * ## Retry with exponential back-off
 * Transient errors are retried up to [maxRetries] times with exponential
 * back-off: `baseDelayMs * 2^attempt` (default: 500ms, 1s, 2s).
 *
 * @property levelRepository  Local repository for reading and updating XP / level data.
 * @property supabaseClient   Remote API client for Supabase PostgREST operations.
 * @property networkMonitor   Checks whether the device has internet connectivity.
 * @property maxRetries       Maximum retry attempts (default 3).
 * @property baseDelayMs      Base delay in milliseconds for exponential back-off (default 500).
 */
class SyncLevelUseCase(
    private val levelRepository: LevelRepository,
    private val supabaseClient: CloudSyncApi,
    private val networkMonitor: NetworkMonitor,
    private val maxRetries: Int = 3,
    private val baseDelayMs: Long = 500L,
) {

    /**
     * Syncs the [UserLevel] record for [userId] with Supabase.
     *
     * @param userId The ID of the user whose level to sync.
     * @return A [SyncLevelResult] describing the outcome.
     * @throws IllegalArgumentException if [userId] is blank.
     * @throws SyncException.NoNetwork if the device has no internet connection.
     */
    suspend operator fun invoke(userId: String): SyncLevelResult {
        require(userId.isNotBlank()) { "userId must not be blank" }

        if (!networkMonitor.isConnected()) {
            throw SyncException.NoNetwork("Cannot sync level: no internet connection")
        }

        return syncWithRetry(userId)
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    /**
     * [CancellationException] is always re-thrown to preserve structured concurrency.
     */
    private suspend fun syncWithRetry(userId: String): SyncLevelResult {
        var lastException: Exception? = null

        repeat(maxRetries) { attempt ->
            try {
                return doSync(userId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiException) {
                if (!e.isTransient) {
                    return SyncLevelResult.Failed(e)
                }
                lastException = e
                delay(baseDelayMs * (1L shl attempt))
            } catch (e: Exception) {
                lastException = e
                delay(baseDelayMs * (1L shl attempt))
            }
        }

        return SyncLevelResult.Failed(lastException ?: Exception("All retries exhausted"))
    }

    private suspend fun doSync(userId: String): SyncLevelResult {
        val local = levelRepository.get(userId)
        val remote = supabaseClient.getUserLevel(userId)

        return when {
            // No local record: pull from remote if available, otherwise nothing to do.
            local == null -> {
                if (remote != null) {
                    levelRepository.addXp(userId, remote.totalXp)
                    SyncLevelResult.PulledFromRemote(remote)
                } else {
                    SyncLevelResult.NoLocalData
                }
            }

            // No remote record: push local XP to Supabase.
            remote == null -> {
                supabaseClient.upsertUserLevel(
                    userId = userId,
                    request = UpsertUserLevelRequest(
                        userId = userId,
                        totalXp = local.totalXp,
                    ),
                )
                SyncLevelResult.Synced
            }

            // Local has more XP (earned offline or on this device): push to remote.
            local.totalXp > remote.totalXp -> {
                supabaseClient.upsertUserLevel(
                    userId = userId,
                    request = UpsertUserLevelRequest(
                        userId = userId,
                        totalXp = local.totalXp,
                    ),
                )
                SyncLevelResult.Synced
            }

            // Remote has more or equal XP (earned on another device): update local.
            else -> {
                if (remote.totalXp > local.totalXp) {
                    val xpDiff = remote.totalXp - local.totalXp
                    levelRepository.addXp(userId, xpDiff)
                    SyncLevelResult.PulledFromRemote(remote)
                } else {
                    // Equal XP — already in sync.
                    SyncLevelResult.AlreadySynced
                }
            }
        }
    }
}

// =============================================================================
// Result type
// =============================================================================

/**
 * Describes the outcome of a [SyncLevelUseCase] invocation.
 */
sealed class SyncLevelResult {

    /** The local XP was successfully pushed to Supabase. */
    data object Synced : SyncLevelResult()

    /** Local and remote XP were already equal -- nothing to do. */
    data object AlreadySynced : SyncLevelResult()

    /** No local level record exists for this user -- nothing to push. */
    data object NoLocalData : SyncLevelResult()

    /**
     * The remote record had higher XP; the local record was updated from the remote.
     *
     * @property remote The authoritative [UserLevel] pulled from Supabase.
     */
    data class PulledFromRemote(val remote: UserLevel) : SyncLevelResult()

    /**
     * The sync failed after all retry attempts.
     *
     * @property cause The last exception that caused the failure.
     */
    data class Failed(val cause: Exception) : SyncLevelResult()
}
