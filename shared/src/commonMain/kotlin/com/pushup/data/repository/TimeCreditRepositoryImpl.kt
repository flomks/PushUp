package com.pushup.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToOneOrNull
import com.pushup.data.mapper.syncStatusToString
import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.repository.TimeCreditRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import kotlinx.datetime.Clock

/**
 * SQLDelight-backed implementation of [TimeCreditRepository].
 *
 * Uses the generated query methods from `Database.sq` and the mappers
 * from [com.pushup.data.mapper] to convert between DB and domain models.
 *
 * The DB schema stores a separate `id` primary key per TimeCredit row,
 * while the domain model uses `userId` as the natural key. This
 * implementation uses `userId` as the `id` for simplicity (the DB
 * has a UNIQUE constraint on `userId`, so this is safe).
 *
 * All suspend functions switch to [dispatcher] to keep callers main-safe.
 *
 * @param database The SQLDelight-generated [PushUpDatabase] instance.
 * @param dispatcher The [CoroutineDispatcher] used for database I/O.
 * @param clock Clock for generating `lastUpdatedAt` timestamps. Defaults to [Clock.System].
 */
class TimeCreditRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
    private val clock: Clock = Clock.System,
) : TimeCreditRepository {

    private val queries get() = database.databaseQueries

    override suspend fun get(userId: String): TimeCredit? = withContext(dispatcher) {
        try {
            queries.selectTimeCreditByUserId(userId).executeAsOneOrNull()?.toDomain()
        } catch (e: Exception) {
            throw RepositoryException("Failed to get time credit for user '$userId'", e)
        }
    }

    override suspend fun update(credit: TimeCredit): Unit = withContext(dispatcher) {
        try {
            val existingRow = queries.selectTimeCreditByUserId(credit.userId).executeAsOneOrNull()
            val rowId = existingRow?.id ?: credit.userId
            queries.upsertTimeCredit(
                id = rowId,
                userId = credit.userId,
                totalEarnedSeconds = credit.totalEarnedSeconds,
                totalSpentSeconds = credit.totalSpentSeconds,
                lastUpdatedAt = credit.lastUpdatedAt.toEpochMilliseconds(),
                syncStatus = syncStatusToString(credit.syncStatus),
            )
        } catch (e: Exception) {
            throw RepositoryException("Failed to update time credit for user '${credit.userId}'", e)
        }
    }

    override suspend fun addEarnedSeconds(userId: String, seconds: Long): Unit =
        withContext(dispatcher) {
            require(seconds > 0) { "seconds must be > 0, was $seconds" }
            try {
                val now = clock.now().toEpochMilliseconds()
                val existing = queries.selectTimeCreditByUserId(userId).executeAsOneOrNull()
                if (existing != null) {
                    queries.updateTimeCredit(
                        totalEarnedSeconds = existing.totalEarnedSeconds + seconds,
                        totalSpentSeconds = existing.totalSpentSeconds,
                        lastUpdatedAt = now,
                        syncStatus = syncStatusToString(SyncStatus.PENDING),
                        id = existing.id,
                    )
                } else {
                    queries.insertTimeCredit(
                        id = userId,
                        userId = userId,
                        totalEarnedSeconds = seconds,
                        totalSpentSeconds = 0,
                        lastUpdatedAt = now,
                        syncStatus = syncStatusToString(SyncStatus.PENDING),
                    )
                }
            } catch (e: Exception) {
                throw RepositoryException(
                    "Failed to add $seconds earned seconds for user '$userId'",
                    e,
                )
            }
        }

    override suspend fun addSpentSeconds(userId: String, seconds: Long): Unit =
        withContext(dispatcher) {
            require(seconds > 0) { "seconds must be > 0, was $seconds" }
            try {
                val now = clock.now().toEpochMilliseconds()
                val existing = queries.selectTimeCreditByUserId(userId).executeAsOneOrNull()
                if (existing != null) {
                    queries.updateTimeCredit(
                        totalEarnedSeconds = existing.totalEarnedSeconds,
                        totalSpentSeconds = existing.totalSpentSeconds + seconds,
                        lastUpdatedAt = now,
                        syncStatus = syncStatusToString(SyncStatus.PENDING),
                        id = existing.id,
                    )
                } else {
                    queries.insertTimeCredit(
                        id = userId,
                        userId = userId,
                        totalEarnedSeconds = 0,
                        totalSpentSeconds = seconds,
                        lastUpdatedAt = now,
                        syncStatus = syncStatusToString(SyncStatus.PENDING),
                    )
                }
            } catch (e: Exception) {
                throw RepositoryException(
                    "Failed to add $seconds spent seconds for user '$userId'",
                    e,
                )
            }
        }

    override suspend fun markAsSynced(userId: String): Unit = withContext(dispatcher) {
        try {
            val existing = queries.selectTimeCreditByUserId(userId).executeAsOneOrNull()
                ?: return@withContext
            queries.updateTimeCredit(
                totalEarnedSeconds = existing.totalEarnedSeconds,
                totalSpentSeconds = existing.totalSpentSeconds,
                lastUpdatedAt = clock.now().toEpochMilliseconds(),
                syncStatus = syncStatusToString(SyncStatus.SYNCED),
                id = existing.id,
            )
        } catch (e: Exception) {
            throw RepositoryException("Failed to mark time credit as synced for user '$userId'", e)
        }
    }

    override fun observeCredit(userId: String): Flow<TimeCredit?> =
        queries.selectTimeCreditByUserId(userId)
            .asFlow()
            .mapToOneOrNull(dispatcher)
            .map { it?.toDomain() }
}
