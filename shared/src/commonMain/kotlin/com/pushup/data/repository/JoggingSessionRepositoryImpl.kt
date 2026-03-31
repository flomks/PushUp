package com.pushup.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import com.pushup.data.mapper.syncStatusToString
import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.repository.JoggingSessionRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/**
 * SQLDelight-backed implementation of [JoggingSessionRepository].
 *
 * The local SQLite database is the source of truth. Cloud sync is handled
 * exclusively by [com.pushup.domain.usecase.sync.SyncJoggingUseCase], which
 * uploads the complete session together with its route points and segments in
 * one atomic operation.
 */
class JoggingSessionRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
    private val clock: Clock = Clock.System,
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
                activeDurationSeconds = session.activeDurationSeconds,
                pauseDurationSeconds = session.pauseDurationSeconds,
                activeDistanceMeters = session.activeDistanceMeters,
                pauseDistanceMeters = session.pauseDistanceMeters,
                pauseCount = session.pauseCount.toLong(),
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
                activeDurationSeconds = session.activeDurationSeconds,
                pauseDurationSeconds = session.pauseDurationSeconds,
                activeDistanceMeters = session.activeDistanceMeters,
                pauseDistanceMeters = session.pauseDistanceMeters,
                pauseCount = session.pauseCount.toLong(),
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
        // NOTE: Background sync is intentionally NOT triggered here.
        // SyncJoggingUseCase is responsible for the complete upload (session +
        // route points + segments). Uploading the session header here would mark
        // it SYNCED before updateSegmentMetrics() runs, causing the server to
        // receive wrong pause/active metrics and preventing route points from
        // ever being uploaded.
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

    override suspend fun updateSegmentMetrics(
        id: String,
        activeDurationSeconds: Long,
        pauseDurationSeconds: Long,
        activeDistanceMeters: Double,
        pauseDistanceMeters: Double,
        pauseCount: Int,
    ): Unit = safeDbCall(
        dispatcher,
        "Failed to update segment metrics for jogging session '$id'",
    ) {
        queries.updateJoggingSegmentMetrics(
            activeDurationSeconds = activeDurationSeconds,
            pauseDurationSeconds = pauseDurationSeconds,
            activeDistanceMeters = activeDistanceMeters,
            pauseDistanceMeters = pauseDistanceMeters,
            pauseCount = pauseCount.toLong(),
            syncStatus = syncStatusToString(SyncStatus.PENDING),
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

}
