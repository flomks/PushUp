package com.pushup.domain.usecase.sync

import com.pushup.data.api.ApiException
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.UpdateWorkoutSessionRequest
import com.pushup.data.api.dto.toCreateRequest
import com.pushup.data.api.isTransient
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.WorkoutSessionRepository
import kotlinx.coroutines.delay

/**
 * Use-case: Upload all locally unsynced [WorkoutSession]s to Supabase.
 *
 * ## Offline-First strategy
 * Sessions are always written to the local SQLite database first with
 * [SyncStatus.PENDING]. This use-case is responsible for the second step:
 * pushing those pending (and previously failed) sessions to the cloud when
 * a network connection is available.
 *
 * Sessions with [SyncStatus.PENDING] or [SyncStatus.FAILED] are both eligible
 * for upload. [SyncStatus.FAILED] sessions from a prior run are retried here,
 * giving them a fresh set of [maxRetries] attempts.
 *
 * ## Conflict resolution -- "Last Write Wins"
 * When a session already exists in Supabase (HTTP 409 Conflict), the use-case
 * compares the local [WorkoutSession.startedAt] timestamp against the remote
 * record's `started_at`. The record with the **later** timestamp wins:
 * - If local is strictly newer → PATCH the remote record.
 * - If remote is newer or equal → discard the local change and mark as SYNCED.
 *
 * In practice, sessions are immutable after they are finished, so conflicts
 * are rare. The "last write wins" rule is a safety net for edge cases such as
 * a session being edited on two devices simultaneously.
 *
 * ## Retry with exponential back-off
 * Transient errors ([ApiException.NetworkError], [ApiException.Timeout],
 * [ApiException.ServiceUnavailable]) are retried up to [maxRetries] times
 * with exponential back-off: `baseDelayMs * 2^attempt` (default: 500ms, 1s, 2s).
 * Non-transient errors (401, 403, etc.) are recorded as [SyncStatus.FAILED]
 * immediately without retrying.
 *
 * ## Result
 * Returns a [SyncWorkoutsResult] summarising how many sessions were uploaded,
 * skipped (conflict resolved in favour of the remote), and failed.
 *
 * @property sessionRepository  Local repository for reading and updating sessions.
 * @property supabaseClient     Remote API client for Supabase PostgREST operations.
 * @property networkMonitor     Checks whether the device has internet connectivity.
 * @property maxRetries         Maximum retry attempts per session (default 3).
 * @property baseDelayMs        Base delay in milliseconds for exponential back-off (default 500).
 */
class SyncWorkoutsUseCase(
    private val sessionRepository: WorkoutSessionRepository,
    private val supabaseClient: CloudSyncApi,
    private val networkMonitor: NetworkMonitor,
    private val maxRetries: Int = 3,
    private val baseDelayMs: Long = 500L,
) {

    /**
     * Uploads all unsynced sessions for [userId] to Supabase.
     *
     * "Unsynced" means [SyncStatus.PENDING] or [SyncStatus.FAILED].
     *
     * @param userId The ID of the user whose sessions to sync.
     * @return A [SyncWorkoutsResult] with counts of synced, skipped, and failed sessions.
     * @throws IllegalArgumentException if [userId] is blank.
     * @throws SyncException.NoNetwork if the device has no internet connection.
     */
    suspend operator fun invoke(userId: String): SyncWorkoutsResult {
        require(userId.isNotBlank()) { "userId must not be blank" }

        if (!networkMonitor.isConnected()) {
            throw SyncException.NoNetwork("Cannot sync workouts: no internet connection")
        }

        val unsynced = sessionRepository.getUnsyncedSessions(userId)
        if (unsynced.isEmpty()) {
            return SyncWorkoutsResult(synced = 0, skipped = 0, failed = 0)
        }

        var synced = 0
        var skipped = 0
        var failed = 0

        for (session in unsynced) {
            when (uploadWithRetry(session)) {
                UploadOutcome.SYNCED  -> synced++
                UploadOutcome.SKIPPED -> skipped++
                UploadOutcome.FAILED  -> failed++
            }
        }

        return SyncWorkoutsResult(synced = synced, skipped = skipped, failed = failed)
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    /**
     * Attempts to upload [session] with up to [maxRetries] attempts.
     *
     * Transient errors are retried with exponential back-off.
     * Non-transient errors (401, 403, etc.) abort immediately and mark the
     * session as [SyncStatus.FAILED].
     */
    private suspend fun uploadWithRetry(session: WorkoutSession): UploadOutcome {
        var lastException: Exception? = null

        repeat(maxRetries) { attempt ->
            try {
                return doUpload(session)
            } catch (e: ApiException) {
                if (!e.isTransient) {
                    // Non-transient error (e.g. 401, 403): mark as FAILED immediately.
                    markFailed(session.id)
                    return UploadOutcome.FAILED
                }
                lastException = e
                delay(baseDelayMs * (1L shl attempt)) // 500ms, 1000ms, 2000ms
            } catch (e: Exception) {
                lastException = e
                delay(baseDelayMs * (1L shl attempt))
            }
        }

        // All retries exhausted.
        markFailed(session.id)
        return UploadOutcome.FAILED
    }

    /**
     * Performs a single upload attempt for [session].
     *
     * On HTTP 409 Conflict, delegates to [resolveConflict] which applies
     * "Last Write Wins" and may throw a transient [ApiException] -- in that
     * case the caller ([uploadWithRetry]) will retry the whole operation.
     */
    private suspend fun doUpload(session: WorkoutSession): UploadOutcome {
        return try {
            supabaseClient.createWorkoutSession(session.toCreateRequest())
            sessionRepository.markAsSynced(session.id)
            UploadOutcome.SYNCED
        } catch (e: ApiException.Conflict) {
            // Session already exists remotely -- apply "Last Write Wins".
            // resolveConflict may throw a transient ApiException; the caller
            // will catch it and retry the entire upload attempt.
            resolveConflict(session)
        }
    }

    /**
     * Resolves a conflict by comparing [WorkoutSession.startedAt] timestamps.
     *
     * - Local is strictly newer → PATCH the remote record, mark local as SYNCED.
     * - Remote is newer or equal → discard local change, mark local as SYNCED.
     *
     * Transient [ApiException]s (network errors, timeouts) are re-thrown so that
     * [uploadWithRetry] can retry the entire operation. Non-transient errors
     * (e.g. 403 Forbidden on the PATCH) mark the session as FAILED.
     *
     * @throws ApiException if a transient error occurs during the remote fetch or patch.
     */
    private suspend fun resolveConflict(local: WorkoutSession): UploadOutcome {
        return try {
            val remote = supabaseClient.getWorkoutSession(local.id)
            if (local.startedAt > remote.startedAt) {
                // Local is newer: overwrite the remote record.
                supabaseClient.updateWorkoutSession(
                    id = local.id,
                    request = UpdateWorkoutSessionRequest(
                        endedAt = local.endedAt?.toString(),
                        pushUpCount = local.pushUpCount,
                        earnedTimeCredits = local.earnedTimeCreditSeconds.toInt(),
                        quality = local.quality,
                    ),
                )
            }
            // Whether we patched or not, the local record is now in sync.
            sessionRepository.markAsSynced(local.id)
            UploadOutcome.SKIPPED
        } catch (e: ApiException) {
            if (e.isTransient) throw e // Let uploadWithRetry handle the retry.
            markFailed(local.id)
            UploadOutcome.FAILED
        }
    }

    private suspend fun markFailed(sessionId: String) {
        try {
            val session = sessionRepository.getById(sessionId) ?: return
            sessionRepository.save(session.copy(syncStatus = SyncStatus.FAILED))
        } catch (_: Exception) {
            // Best-effort: if we can't update the local DB, ignore.
        }
    }

    private enum class UploadOutcome { SYNCED, SKIPPED, FAILED }
}

// =============================================================================
// Result type
// =============================================================================

/**
 * Summary of a [SyncWorkoutsUseCase] invocation.
 *
 * @property synced  Number of sessions successfully uploaded to Supabase.
 * @property skipped Number of sessions where a conflict was resolved in favour
 *   of the remote record (local change discarded, session marked SYNCED).
 * @property failed  Number of sessions that could not be synced after all retries.
 */
data class SyncWorkoutsResult(
    val synced: Int,
    val skipped: Int,
    val failed: Int,
) {
    /** `true` when every unsynced session was handled without a permanent failure. */
    val isFullSuccess: Boolean get() = failed == 0
}
