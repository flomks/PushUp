package com.pushup.domain.usecase.sync

import com.pushup.data.api.ApiException
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.isTransient
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.TimeCreditRepository
import com.pushup.domain.repository.WorkoutSessionRepository
import kotlinx.coroutines.delay

/**
 * Use-case: Download the latest data from Supabase and merge it into the local database.
 *
 * This is the "pull" half of the sync cycle. It is typically invoked:
 * - After a successful login on a new device (to restore all cloud data locally).
 * - Periodically in the background to pick up changes made on other devices.
 * - After a successful upload ([SyncWorkoutsUseCase] / [SyncTimeCreditUseCase])
 *   to confirm the server state.
 *
 * ## Conflict resolution -- "Last Write Wins"
 * For each remote record, the use-case compares timestamps with the local copy:
 *
 * ### WorkoutSessions
 * Comparison field: [WorkoutSession.startedAt]
 * - Remote is strictly newer → overwrite local.
 * - Local is newer or equal → keep local (do not overwrite).
 * - No local copy → insert remote record.
 *
 * ### TimeCredit
 * Comparison field: [TimeCredit.lastUpdatedAt]
 * - Remote is strictly newer → overwrite local.
 * - Local is newer or equal → keep local.
 * - No local copy → insert remote record.
 *
 * ## Retry with exponential back-off
 * Transient network errors are retried up to [maxRetries] times with
 * exponential back-off: `baseDelayMs * 2^attempt` (default: 500ms, 1s, 2s).
 * Non-transient errors (401, 403, etc.) abort immediately without retrying.
 *
 * @property sessionRepository    Local repository for workout sessions.
 * @property timeCreditRepository Local repository for time credits.
 * @property supabaseClient       Remote API client for Supabase PostgREST operations.
 * @property networkMonitor       Checks whether the device has internet connectivity.
 * @property maxRetries           Maximum retry attempts (default 3).
 * @property baseDelayMs          Base delay in milliseconds for exponential back-off (default 500).
 */
class SyncFromCloudUseCase(
    private val sessionRepository: WorkoutSessionRepository,
    private val timeCreditRepository: TimeCreditRepository,
    private val supabaseClient: CloudSyncApi,
    private val networkMonitor: NetworkMonitor,
    private val maxRetries: Int = 3,
    private val baseDelayMs: Long = 500L,
) {

    /**
     * Downloads all data for [userId] from Supabase and merges it locally.
     *
     * @param userId The ID of the user whose cloud data to pull.
     * @return A [SyncFromCloudResult] summarising what was downloaded and merged.
     * @throws IllegalArgumentException if [userId] is blank.
     * @throws SyncException.NoNetwork if the device has no internet connection.
     */
    suspend operator fun invoke(userId: String): SyncFromCloudResult {
        require(userId.isNotBlank()) { "userId must not be blank" }

        if (!networkMonitor.isConnected()) {
            throw SyncException.NoNetwork("Cannot sync from cloud: no internet connection")
        }

        val sessionsResult = fetchAndMergeSessions()
        val timeCreditSynced = fetchAndMergeTimeCredit(userId)

        return SyncFromCloudResult(
            sessionsDownloaded = sessionsResult.downloaded,
            sessionsInsertedOrUpdated = sessionsResult.insertedOrUpdated,
            sessionsKeptLocal = sessionsResult.keptLocal,
            sessionsFailed = sessionsResult.failed,
            timeCreditSynced = timeCreditSynced,
        )
    }

    // =========================================================================
    // WorkoutSession pull
    // =========================================================================

    private data class SessionsMergeResult(
        val downloaded: Int,
        val insertedOrUpdated: Int,
        val keptLocal: Int,
        val failed: Int,
    )

    private suspend fun fetchAndMergeSessions(): SessionsMergeResult {
        val remoteSessions = fetchRemoteSessionsWithRetry()
            ?: return SessionsMergeResult(downloaded = 0, insertedOrUpdated = 0, keptLocal = 0, failed = 1)

        var insertedOrUpdated = 0
        var keptLocal = 0
        var failed = 0

        for (remote in remoteSessions) {
            try {
                val wrote = mergeSession(remote)
                if (wrote) insertedOrUpdated++ else keptLocal++
            } catch (_: Exception) {
                failed++
            }
        }

        return SessionsMergeResult(
            downloaded = remoteSessions.size,
            insertedOrUpdated = insertedOrUpdated,
            keptLocal = keptLocal,
            failed = failed,
        )
    }

    private suspend fun fetchRemoteSessionsWithRetry(): List<WorkoutSession>? {
        repeat(maxRetries) { attempt ->
            try {
                return supabaseClient.getWorkoutSessions()
            } catch (e: ApiException) {
                if (!e.isTransient) return null
                delay(baseDelayMs * (1L shl attempt))
            } catch (_: Exception) {
                delay(baseDelayMs * (1L shl attempt))
            }
        }
        return null
    }

    /**
     * Merges a single remote [WorkoutSession] into the local database.
     *
     * "Last Write Wins" on [WorkoutSession.startedAt]:
     * - No local copy → insert remote (marked SYNCED). Returns `true`.
     * - Remote is strictly newer → overwrite local. Returns `true`.
     * - Local is newer or equal → keep local unchanged. Returns `false`.
     *
     * @return `true` if the local database was written, `false` if local was kept.
     */
    private suspend fun mergeSession(remote: WorkoutSession): Boolean {
        val local = sessionRepository.getById(remote.id)
        return when {
            local == null -> {
                // New record from cloud -- insert it locally as SYNCED.
                sessionRepository.save(remote.copy(syncStatus = SyncStatus.SYNCED))
                true
            }
            remote.startedAt > local.startedAt -> {
                // Remote is newer -- overwrite local.
                sessionRepository.save(remote.copy(syncStatus = SyncStatus.SYNCED))
                true
            }
            else -> {
                // Local is newer or equal -- keep local, do not overwrite.
                // The upload use-case will push the local version on the next sync.
                false
            }
        }
    }

    // =========================================================================
    // TimeCredit pull
    // =========================================================================

    private suspend fun fetchAndMergeTimeCredit(userId: String): Boolean {
        repeat(maxRetries) { attempt ->
            try {
                val remote = supabaseClient.getTimeCredit(userId)
                if (remote != null) {
                    mergeTimeCredit(userId, remote)
                }
                return true
            } catch (e: ApiException) {
                if (!e.isTransient) return false
                delay(baseDelayMs * (1L shl attempt))
            } catch (_: Exception) {
                delay(baseDelayMs * (1L shl attempt))
            }
        }
        return false
    }

    /**
     * Merges the remote [TimeCredit] into the local database.
     *
     * "Last Write Wins" on [TimeCredit.lastUpdatedAt]:
     * - No local copy → insert remote (marked SYNCED).
     * - Remote is strictly newer → overwrite local.
     * - Local is newer or equal → keep local unchanged.
     */
    private suspend fun mergeTimeCredit(userId: String, remote: TimeCredit) {
        val local = timeCreditRepository.get(userId)
        when {
            local == null -> {
                timeCreditRepository.update(remote.copy(syncStatus = SyncStatus.SYNCED))
            }
            remote.lastUpdatedAt > local.lastUpdatedAt -> {
                timeCreditRepository.update(remote.copy(syncStatus = SyncStatus.SYNCED))
            }
            else -> {
                // Local is newer or equal -- keep local.
            }
        }
    }
}

// =============================================================================
// Result type
// =============================================================================

/**
 * Summary of a [SyncFromCloudUseCase] invocation.
 *
 * @property sessionsDownloaded      Total number of remote sessions received from the server.
 * @property sessionsInsertedOrUpdated Number of sessions that were written to the local database
 *   (either newly inserted or overwritten because the remote was newer).
 * @property sessionsKeptLocal       Number of sessions where the local copy was newer or equal
 *   and was therefore kept unchanged.
 * @property sessionsFailed          Number of sessions that could not be merged (parse errors, etc.).
 * @property timeCreditSynced        `true` if the time-credit record was successfully pulled.
 */
data class SyncFromCloudResult(
    val sessionsDownloaded: Int,
    val sessionsInsertedOrUpdated: Int,
    val sessionsKeptLocal: Int,
    val sessionsFailed: Int,
    val timeCreditSynced: Boolean,
) {
    /** `true` when the pull completed without any failures. */
    val isFullSuccess: Boolean get() = sessionsFailed == 0 && timeCreditSynced
}
