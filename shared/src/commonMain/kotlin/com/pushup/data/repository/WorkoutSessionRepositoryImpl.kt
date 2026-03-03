package com.pushup.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import com.pushup.data.mapper.syncStatusToString
import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.WorkoutSessionRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/**
 * SQLDelight-backed implementation of [WorkoutSessionRepository].
 *
 * Uses the generated query methods from `Database.sq` and the mappers
 * from [com.pushup.data.mapper] to convert between DB and domain models.
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
) : WorkoutSessionRepository {

    private val queries get() = database.databaseQueries

    override suspend fun save(session: WorkoutSession): Unit = safeDbCall(
        dispatcher,
        "Failed to save workout session '${session.id}'",
    ) {
        val now = clock.now().toEpochMilliseconds()
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
    }

    override suspend fun getById(id: String): WorkoutSession? = safeDbCall(
        dispatcher,
        "Failed to get workout session '$id'",
    ) {
        queries.selectWorkoutSessionById(id).executeAsOneOrNull()?.toDomain()
    }

    override suspend fun getAllByUserId(userId: String): List<WorkoutSession> = safeDbCall(
        dispatcher,
        "Failed to get workout sessions for user '$userId'",
    ) {
        queries.selectWorkoutSessionsByUserId(userId).executeAsList().map { it.toDomain() }
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
}
