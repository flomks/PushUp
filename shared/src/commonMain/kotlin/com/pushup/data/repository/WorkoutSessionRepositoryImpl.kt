package com.pushup.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.toCreateRequest
import com.pushup.data.mapper.syncStatusToString
import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.WorkoutSessionRepository
import com.pushup.domain.usecase.sync.NetworkMonitor
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/**
 * SQLDelight-backed implementation of [WorkoutSessionRepository] with optional
 * cloud-sync support.
 *
 * ## Offline-First / Cache Strategy
 * The local SQLite database is the **source of truth**. The cloud (Supabase) is
 * a backup and sync target:
 *
 * - **save()**: Persists locally with [SyncStatus.PENDING], then fires a
 *   background coroutine to push the session to Supabase. The caller is not
 *   blocked by the network operation.
 *
 * - **getAllByUserId()**: Returns local data immediately. If [cloudSyncApi] and
 *   [networkMonitor] are provided and the device is online, a background merge
 *   of cloud sessions is also triggered so that subsequent reads reflect the
 *   latest server state.
 *
 * ## Cloud sync is optional
 * [cloudSyncApi] and [networkMonitor] are nullable. When either is `null` the
 * repository behaves exactly like the original local-only implementation. This
 * allows the repository to be used in tests and in guest-mode (not logged in)
 * without any API wiring.
 *
 * ## Background sync scope
 * Background sync jobs are launched in [syncScope]. The default scope uses a
 * [SupervisorJob] so that individual sync failures do not cancel the scope.
 * Override [syncScope] in tests to control coroutine execution.
 *
 * The [save] method uses an atomic `INSERT OR REPLACE` (upsert) to avoid
 * read-then-write race conditions.
 *
 * All suspend functions are main-safe -- dispatcher switching is handled
 * by [safeDbCall].
 */
class WorkoutSessionRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
    private val clock: Clock = Clock.System,
    private val cloudSyncApi: CloudSyncApi? = null,
    private val networkMonitor: NetworkMonitor? = null,
    private val syncScope: CoroutineScope = CoroutineScope(SupervisorJob()),
) : WorkoutSessionRepository {

    private val queries get() = database.databaseQueries

    /**
     * Persists [session] locally preserving its [WorkoutSession.syncStatus],
     * then triggers a background upload to Supabase if the status is [SyncStatus.PENDING]
     * and the device is online.
     *
     * The caller is never blocked by the network operation.
     */
    override suspend fun save(session: WorkoutSession): Unit = safeDbCall(
        dispatcher,
        "Failed to save workout session '${session.id}'",
    ) {
        val now = clock.now().toEpochMilliseconds()
        // Always persist locally first -- offline-first guarantee.
        // Preserve the caller's syncStatus exactly:
        //   SYNCED -> already on server, no upload needed.
        //   FAILED -> explicitly marked failed by SyncWorkoutsUseCase, keep as-is.
        //   PENDING -> needs upload, trigger background sync.
        queries.upsertWorkoutSession(
            id = session.id,
            userId = session.userId,
            startedAt = session.startedAt.toEpochMilliseconds(),
            endedAt = session.endedAt?.toEpochMilliseconds(),
            pushUpCount = session.pushUpCount.toLong(),
            earnedTimeCredits = session.earnedTimeCreditSeconds,
            quality = session.quality.toDouble(),
            syncStatus = syncStatusToString(session.syncStatus),
            updatedAt = now,
        )

        // Fire-and-forget background sync only for PENDING sessions.
        // SYNCED sessions are already on the server; FAILED sessions are
        // handled by SyncWorkoutsUseCase on the next sync cycle.
        if (session.syncStatus == SyncStatus.PENDING) {
            triggerBackgroundSync(session)
        }
    }

    override suspend fun getById(id: String): WorkoutSession? = safeDbCall(
        dispatcher,
        "Failed to get workout session '$id'",
    ) {
        queries.selectWorkoutSessionById(id).executeAsOneOrNull()?.toDomain()
    }

    /**
     * Returns all sessions for [userId] from the local database.
     *
     * If cloud sync is configured and the device is online, a background merge
     * of cloud sessions is triggered so that subsequent reads reflect the latest
     * server state. The current call always returns local data immediately.
     */
    override suspend fun getAllByUserId(userId: String): List<WorkoutSession> = safeDbCall(
        dispatcher,
        "Failed to get workout sessions for user '$userId'",
    ) {
        val localSessions = queries.selectWorkoutSessionsByUserId(userId)
            .executeAsList()
            .map { it.toDomain() }

        // Trigger a background cloud merge so the next read is up-to-date.
        triggerBackgroundCloudMerge(userId)

        localSessions
    }

    override suspend fun getByDateRange(
        userId: String,
        from: Instant,
        to: Instant,
    ): List<WorkoutSession> = safeDbCall(
        dispatcher,
        "Failed to get workout sessions for user '$userId' in date range",
    ) {
        queries.selectWorkoutSessionsByDateRange(
            userId = userId,
            startedAt = from.toEpochMilliseconds(),
            startedAt_ = to.toEpochMilliseconds(),
        ).executeAsList().map { it.toDomain() }
    }

    override suspend fun getUnsyncedSessions(userId: String): List<WorkoutSession> = safeDbCall(
        dispatcher,
        "Failed to get unsynced sessions for user '$userId'",
    ) {
        queries.selectUnsyncedSessionsByUserId(userId).executeAsList().map { it.toDomain() }
    }

    override suspend fun updateStats(id: String, pushUpCount: Int, quality: Float): Unit = safeDbCall(
        dispatcher,
        "Failed to update stats for session '$id'",
    ) {
        queries.updateWorkoutSessionStats(
            pushUpCount = pushUpCount.toLong(),
            quality = quality.toDouble(),
            syncStatus = syncStatusToString(SyncStatus.PENDING),
            updatedAt = clock.now().toEpochMilliseconds(),
            id = id,
        )
    }

    override suspend fun finishSession(
        id: String,
        endedAt: Instant,
        earnedTimeCreditSeconds: Long,
    ): Unit = safeDbCall(
        dispatcher,
        "Failed to finish session '$id'",
    ) {
        queries.updateWorkoutSessionEnd(
            endedAt = endedAt.toEpochMilliseconds(),
            earnedTimeCredits = earnedTimeCreditSeconds,
            syncStatus = syncStatusToString(SyncStatus.PENDING),
            updatedAt = clock.now().toEpochMilliseconds(),
            id = id,
        )
        // Trigger background sync for the finished session.
        val session = queries.selectWorkoutSessionById(id).executeAsOneOrNull()?.toDomain()
        if (session != null) {
            triggerBackgroundSync(session)
        }
    }

    override suspend fun markAsSynced(id: String): Unit = safeDbCall(
        dispatcher,
        "Failed to mark session '$id' as synced",
    ) {
        queries.updateWorkoutSessionSyncStatus(
            syncStatus = syncStatusToString(SyncStatus.SYNCED),
            updatedAt = clock.now().toEpochMilliseconds(),
            id = id,
        )
    }

    override suspend fun delete(id: String): Unit = safeDbCall(
        dispatcher,
        "Failed to delete workout session '$id'",
    ) {
        queries.deleteWorkoutSession(id)
    }

    override fun observeAllByUserId(userId: String): Flow<List<WorkoutSession>> =
        queries.selectWorkoutSessionsByUserId(userId)
            .asFlow()
            .mapToList(dispatcher)
            .map { list -> list.map { it.toDomain() } }
            .catch { e ->
                throw RepositoryException(
                    "Failed to observe sessions for user '$userId'",
                    e,
                )
            }

    // =========================================================================
    // Private cloud-sync helpers
    // =========================================================================

    /**
     * Launches a fire-and-forget coroutine that uploads [session] to Supabase.
     *
     * Failures are silently swallowed -- the session remains [SyncStatus.PENDING]
     * in the local DB and will be retried by [SyncWorkoutsUseCase] on the next
     * sync cycle.
     */
    private fun triggerBackgroundSync(session: WorkoutSession) {
        val api = cloudSyncApi ?: return
        val monitor = networkMonitor ?: return

        syncScope.launch {
            try {
                if (!monitor.isConnected()) return@launch
                try {
                    api.createWorkoutSession(session.toCreateRequest())
                } catch (_: Exception) {
                    // Session already exists on server -- attempt an update.
                    try {
                        api.updateWorkoutSession(
                            id = session.id,
                            request = com.pushup.data.api.dto.UpdateWorkoutSessionRequest(
                                endedAt = session.endedAt?.toString(),
                                pushUpCount = session.pushUpCount,
                                earnedTimeCredits = session.earnedTimeCreditSeconds.toInt(),
                                quality = session.quality,
                            ),
                        )
                    } catch (_: Exception) {
                        return@launch
                    }
                }
                // Mark as synced in the local DB.
                safeDbCall(dispatcher, "Failed to mark session '${session.id}' as synced after background sync") {
                    queries.updateWorkoutSessionSyncStatus(
                        syncStatus = syncStatusToString(SyncStatus.SYNCED),
                        updatedAt = clock.now().toEpochMilliseconds(),
                        id = session.id,
                    )
                }
            } catch (_: Exception) {
                // Best-effort: failures are retried by SyncWorkoutsUseCase.
            }
        }
    }

    /**
     * Launches a fire-and-forget coroutine that fetches all sessions for [userId]
     * from Supabase and merges them into the local database using "Last Write Wins"
     * on [WorkoutSession.startedAt].
     *
     * This keeps the local DB up-to-date with changes made on other devices without
     * blocking the current read.
     */
    private fun triggerBackgroundCloudMerge(userId: String) {
        val api = cloudSyncApi ?: return
        val monitor = networkMonitor ?: return

        syncScope.launch {
            try {
                if (!monitor.isConnected()) return@launch
                val remoteSessions = api.getWorkoutSessions()
                for (remote in remoteSessions) {
                    if (remote.userId != userId) continue
                    try {
                        val local = safeDbCall(dispatcher, "") {
                            queries.selectWorkoutSessionById(remote.id).executeAsOneOrNull()?.toDomain()
                        }
                        val shouldWrite = local == null || remote.startedAt > local.startedAt
                        if (shouldWrite) {
                            safeDbCall(dispatcher, "Failed to merge remote session '${remote.id}'") {
                                queries.upsertWorkoutSession(
                                    id = remote.id,
                                    userId = remote.userId,
                                    startedAt = remote.startedAt.toEpochMilliseconds(),
                                    endedAt = remote.endedAt?.toEpochMilliseconds(),
                                    pushUpCount = remote.pushUpCount.toLong(),
                                    earnedTimeCredits = remote.earnedTimeCreditSeconds,
                                    quality = remote.quality.toDouble(),
                                    syncStatus = syncStatusToString(SyncStatus.SYNCED),
                                    updatedAt = clock.now().toEpochMilliseconds(),
                                )
                            }
                        }
                    } catch (_: Exception) {
                        // Skip individual merge failures -- best-effort.
                    }
                }
            } catch (_: Exception) {
                // Best-effort: full merge failures are handled by SyncFromCloudUseCase.
            }
        }
    }
}
