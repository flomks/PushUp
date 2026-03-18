package com.pushup.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.UpdateJoggingSessionRequest
import com.pushup.data.api.dto.toCreateRequest
import com.pushup.data.mapper.syncStatusToString
import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.repository.JoggingSessionRepository
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
 * SQLDelight-backed implementation of [JoggingSessionRepository] with optional
 * cloud-sync support.
 *
 * Follows the same offline-first pattern as [WorkoutSessionRepositoryImpl]:
 * the local SQLite database is the source of truth. When [cloudSyncApi] and
 * [networkMonitor] are provided, finished sessions are uploaded in the background.
 */
class JoggingSessionRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
    private val clock: Clock = Clock.System,
    private val cloudSyncApi: CloudSyncApi? = null,
    private val networkMonitor: NetworkMonitor? = null,
    private val syncScope: CoroutineScope = CoroutineScope(SupervisorJob()),
) : JoggingSessionRepository {

    private val queries get() = database.databaseQueries

    /**
     * Saves a jogging session using UPDATE-first, INSERT-fallback strategy.
     *
     * **Why not INSERT OR REPLACE?**
     * SQLite implements INSERT OR REPLACE as DELETE + INSERT. Because the
     * [RoutePoint] table has `ON DELETE CASCADE` on `sessionId`, a REPLACE
     * silently deletes all route points for the session. This UPDATE-first
     * approach preserves child rows.
     */
    override suspend fun save(session: JoggingSession): Unit = safeDbCall(
        dispatcher,
        "Failed to save jogging session '${session.id}'",
    ) {
        val now = clock.now().toEpochMilliseconds()
        val existing = queries.selectJoggingSessionById(session.id).executeAsOneOrNull()
        if (existing != null) {
            // UPDATE existing row -- preserves RoutePoint child rows
            queries.updateJoggingSession(
                startedAt = session.startedAt.toEpochMilliseconds(),
                endedAt = session.endedAt?.toEpochMilliseconds(),
                distanceMeters = session.distanceMeters,
                durationSeconds = session.durationSeconds,
                avgPaceSecondsPerKm = session.avgPaceSecondsPerKm?.toLong(),
                caloriesBurned = session.caloriesBurned.toLong(),
                earnedTimeCredits = session.earnedTimeCreditSeconds,
                syncStatus = syncStatusToString(session.syncStatus),
                updatedAt = now,
                id = session.id,
            )
        } else {
            // INSERT new row -- no child rows to lose
            queries.insertJoggingSession(
                id = session.id,
                userId = session.userId,
                startedAt = session.startedAt.toEpochMilliseconds(),
                endedAt = session.endedAt?.toEpochMilliseconds(),
                distanceMeters = session.distanceMeters,
                durationSeconds = session.durationSeconds,
                avgPaceSecondsPerKm = session.avgPaceSecondsPerKm?.toLong(),
                caloriesBurned = session.caloriesBurned.toLong(),
                earnedTimeCredits = session.earnedTimeCreditSeconds,
                syncStatus = syncStatusToString(session.syncStatus),
                updatedAt = now,
            )
        }
    }

    override suspend fun getById(id: String): JoggingSession? = safeDbCall(
        dispatcher,
        "Failed to get jogging session '$id'",
    ) {
        queries.selectJoggingSessionById(id).executeAsOneOrNull()?.toDomain()
    }

    override suspend fun getAllByUserId(userId: String): List<JoggingSession> = safeDbCall(
        dispatcher,
        "Failed to get jogging sessions for user '$userId'",
    ) {
        queries.selectJoggingSessionsByUserId(userId)
            .executeAsList()
            .map { it.toDomain() }
    }

    override suspend fun getByDateRange(
        userId: String,
        from: Instant,
        to: Instant,
    ): List<JoggingSession> = safeDbCall(
        dispatcher,
        "Failed to get jogging sessions for user '$userId' in date range",
    ) {
        queries.selectJoggingSessionsByDateRange(
            userId = userId,
            startedAt = from.toEpochMilliseconds(),
            startedAt_ = to.toEpochMilliseconds(),
        ).executeAsList().map { it.toDomain() }
    }

    override suspend fun getUnsyncedSessions(userId: String): List<JoggingSession> = safeDbCall(
        dispatcher,
        "Failed to get unsynced jogging sessions for user '$userId'",
    ) {
        queries.selectUnsyncedJoggingSessionsByUserId(userId).executeAsList().map { it.toDomain() }
    }

    override suspend fun updateStats(
        id: String,
        distanceMeters: Double,
        durationSeconds: Long,
        avgPaceSecondsPerKm: Int?,
        caloriesBurned: Int,
    ): Unit = safeDbCall(
        dispatcher,
        "Failed to update stats for jogging session '$id'",
    ) {
        queries.updateJoggingSessionStats(
            distanceMeters = distanceMeters,
            durationSeconds = durationSeconds,
            avgPaceSecondsPerKm = avgPaceSecondsPerKm?.toLong(),
            caloriesBurned = caloriesBurned.toLong(),
            syncStatus = syncStatusToString(SyncStatus.PENDING),
            updatedAt = clock.now().toEpochMilliseconds(),
            id = id,
        )
    }

    override suspend fun finishSession(
        id: String,
        endedAt: Instant,
        distanceMeters: Double,
        durationSeconds: Long,
        avgPaceSecondsPerKm: Int?,
        caloriesBurned: Int,
        earnedTimeCreditSeconds: Long,
    ): Unit = safeDbCall(
        dispatcher,
        "Failed to finish jogging session '$id'",
    ) {
        queries.updateJoggingSessionEnd(
            endedAt = endedAt.toEpochMilliseconds(),
            distanceMeters = distanceMeters,
            durationSeconds = durationSeconds,
            avgPaceSecondsPerKm = avgPaceSecondsPerKm?.toLong(),
            caloriesBurned = caloriesBurned.toLong(),
            earnedTimeCredits = earnedTimeCreditSeconds,
            syncStatus = syncStatusToString(SyncStatus.PENDING),
            updatedAt = clock.now().toEpochMilliseconds(),
            id = id,
        )
        // Trigger background sync for the finished session.
        val session = queries.selectJoggingSessionById(id).executeAsOneOrNull()?.toDomain()
        if (session != null) {
            triggerBackgroundSync(session)
        }
    }

    override suspend fun markAsSynced(id: String): Unit = safeDbCall(
        dispatcher,
        "Failed to mark jogging session '$id' as synced",
    ) {
        queries.updateJoggingSessionSyncStatus(
            syncStatus = syncStatusToString(SyncStatus.SYNCED),
            updatedAt = clock.now().toEpochMilliseconds(),
            id = id,
        )
    }

    override suspend fun delete(id: String): Unit = safeDbCall(
        dispatcher,
        "Failed to delete jogging session '$id'",
    ) {
        queries.deleteJoggingSession(id)
    }

    override fun observeAllByUserId(userId: String): Flow<List<JoggingSession>> =
        queries.selectJoggingSessionsByUserId(userId)
            .asFlow()
            .mapToList(dispatcher)
            .map { list -> list.map { it.toDomain() } }
            .catch { e ->
                throw RepositoryException(
                    "Failed to observe jogging sessions for user '$userId'",
                    e,
                )
            }

    // =========================================================================
    // Private cloud-sync helpers
    // =========================================================================

    /**
     * Launches a fire-and-forget coroutine that uploads [session] to Supabase.
     *
     * Only completed sessions (endedAt != null) are uploaded. Failures are
     * silently swallowed -- the session remains PENDING and will be retried
     * by [SyncJoggingUseCase] on the next sync cycle.
     */
    private fun triggerBackgroundSync(session: JoggingSession) {
        val api = cloudSyncApi ?: return
        val monitor = networkMonitor ?: return

        if (session.endedAt == null) return

        syncScope.launch {
            try {
                if (!monitor.isConnected()) return@launch
                try {
                    api.createJoggingSession(session.toCreateRequest())
                } catch (_: Exception) {
                    // Session already exists -- attempt update.
                    try {
                        api.updateJoggingSession(
                            id = session.id,
                            request = UpdateJoggingSessionRequest(
                                endedAt = session.endedAt.toString(),
                                distanceMeters = session.distanceMeters.toFloat(),
                                durationSeconds = session.durationSeconds.toInt(),
                                avgPaceSecondsPerKm = session.avgPaceSecondsPerKm,
                                caloriesBurned = session.caloriesBurned,
                                earnedTimeCredits = session.earnedTimeCreditSeconds.toInt(),
                            ),
                        )
                    } catch (_: Exception) {
                        return@launch
                    }
                }
                // Mark as synced in the local DB.
                safeDbCall(dispatcher, "Failed to mark session '${session.id}' as synced after background sync") {
                    queries.updateJoggingSessionSyncStatus(
                        syncStatus = syncStatusToString(SyncStatus.SYNCED),
                        updatedAt = clock.now().toEpochMilliseconds(),
                        id = session.id,
                    )
                }
            } catch (_: Exception) {
                // Best-effort: failures are retried by SyncJoggingUseCase.
            }
        }
    }
}
