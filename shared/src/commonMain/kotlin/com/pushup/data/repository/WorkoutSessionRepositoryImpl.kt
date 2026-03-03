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
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/**
 * SQLDelight-backed implementation of [WorkoutSessionRepository].
 *
 * Uses the generated query methods from `Database.sq` and the mappers
 * from [com.pushup.data.mapper] to convert between DB and domain models.
 *
 * All suspend functions switch to [dispatcher] to keep callers main-safe.
 *
 * @param database The SQLDelight-generated [PushUpDatabase] instance.
 * @param dispatcher The [CoroutineDispatcher] used for database I/O.
 * @param clock Clock for generating `updatedAt` timestamps. Defaults to [Clock.System].
 */
class WorkoutSessionRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
    private val clock: Clock = Clock.System,
) : WorkoutSessionRepository {

    private val queries get() = database.databaseQueries

    override suspend fun save(session: WorkoutSession): Unit = withContext(dispatcher) {
        try {
            val now = clock.now().toEpochMilliseconds()
            val existing = queries.selectWorkoutSessionById(session.id).executeAsOneOrNull()
            if (existing != null) {
                queries.updateWorkoutSession(
                    startedAt = session.startedAt.toEpochMilliseconds(),
                    endedAt = session.endedAt?.toEpochMilliseconds(),
                    pushUpCount = session.pushUpCount.toLong(),
                    earnedTimeCredits = session.earnedTimeCreditSeconds,
                    quality = session.quality.toDouble(),
                    syncStatus = syncStatusToString(session.syncStatus),
                    updatedAt = now,
                    id = session.id,
                )
            } else {
                queries.insertWorkoutSession(
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
        } catch (e: Exception) {
            throw RepositoryException("Failed to save workout session '${session.id}'", e)
        }
    }

    override suspend fun getById(id: String): WorkoutSession? = withContext(dispatcher) {
        try {
            queries.selectWorkoutSessionById(id).executeAsOneOrNull()?.toDomain()
        } catch (e: Exception) {
            throw RepositoryException("Failed to get workout session '$id'", e)
        }
    }

    override suspend fun getAllByUserId(userId: String): List<WorkoutSession> =
        withContext(dispatcher) {
            try {
                queries.selectWorkoutSessionsByUserId(userId).executeAsList().map { it.toDomain() }
            } catch (e: Exception) {
                throw RepositoryException("Failed to get workout sessions for user '$userId'", e)
            }
        }

    override suspend fun getByDateRange(
        userId: String,
        from: Instant,
        to: Instant,
    ): List<WorkoutSession> = withContext(dispatcher) {
        try {
            queries.selectWorkoutSessionsByDateRange(
                userId = userId,
                startedAt = from.toEpochMilliseconds(),
                startedAt_ = to.toEpochMilliseconds(),
            ).executeAsList().map { it.toDomain() }
        } catch (e: Exception) {
            throw RepositoryException(
                "Failed to get workout sessions for user '$userId' in date range",
                e,
            )
        }
    }

    override suspend fun getUnsyncedSessions(userId: String): List<WorkoutSession> =
        withContext(dispatcher) {
            try {
                queries.selectUnsyncedSessions().executeAsList()
                    .filter { it.userId == userId }
                    .map { it.toDomain() }
            } catch (e: Exception) {
                throw RepositoryException(
                    "Failed to get unsynced sessions for user '$userId'",
                    e,
                )
            }
        }

    override suspend fun markAsSynced(id: String): Unit = withContext(dispatcher) {
        try {
            queries.updateWorkoutSessionSyncStatus(
                syncStatus = syncStatusToString(SyncStatus.SYNCED),
                updatedAt = clock.now().toEpochMilliseconds(),
                id = id,
            )
        } catch (e: Exception) {
            throw RepositoryException("Failed to mark session '$id' as synced", e)
        }
    }

    override suspend fun delete(id: String): Unit = withContext(dispatcher) {
        try {
            queries.deleteWorkoutSession(id)
        } catch (e: Exception) {
            throw RepositoryException("Failed to delete workout session '$id'", e)
        }
    }

    override fun observeAllByUserId(userId: String): Flow<List<WorkoutSession>> =
        queries.selectWorkoutSessionsByUserId(userId)
            .asFlow()
            .mapToList(dispatcher)
            .map { list -> list.map { it.toDomain() } }
}
