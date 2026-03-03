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
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.datetime.Clock

/**
 * SQLDelight-backed implementation of [TimeCreditRepository].
 *
 * Uses the generated query methods from `Database.sq` and the mappers
 * from [com.pushup.data.mapper] to convert between DB and domain models.
 *
 * All read-modify-write operations are wrapped in a [database.transaction]
 * to prevent lost-update anomalies.
 *
 * All suspend functions are main-safe -- dispatcher switching is handled
 * by [safeDbCall].
 */
class TimeCreditRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
    private val clock: Clock = Clock.System,
) : TimeCreditRepository {

    private val queries get() = database.databaseQueries

    override suspend fun get(userId: String): TimeCredit? = safeDbCall(
        dispatcher,
        "Failed to get time credit for user '$userId'",
    ) {
        queries.selectTimeCreditByUserId(userId).executeAsOneOrNull()?.toDomain()
    }

    override suspend fun update(credit: TimeCredit): Unit = safeDbCall(
        dispatcher,
        "Failed to update time credit for user '${credit.userId}'",
    ) {
        database.transaction {
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
        }
    }

    override suspend fun addEarnedSeconds(userId: String, seconds: Long): Unit {
        require(seconds > 0) { "seconds must be > 0, was $seconds" }
        safeDbCall(
            dispatcher,
            "Failed to add $seconds earned seconds for user '$userId'",
        ) {
            val now = clock.now().toEpochMilliseconds()
            database.transaction {
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
            }
        }
    }

    override suspend fun addSpentSeconds(userId: String, seconds: Long): Unit {
        require(seconds > 0) { "seconds must be > 0, was $seconds" }
        safeDbCall(
            dispatcher,
            "Failed to add $seconds spent seconds for user '$userId'",
        ) {
            val now = clock.now().toEpochMilliseconds()
            database.transaction {
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
            }
        }
    }

    override suspend fun markAsSynced(userId: String): Unit = safeDbCall(
        dispatcher,
        "Failed to mark time credit as synced for user '$userId'",
    ) {
        database.transaction {
            val existing = queries.selectTimeCreditByUserId(userId).executeAsOneOrNull()
                ?: return@transaction
            queries.updateTimeCredit(
                totalEarnedSeconds = existing.totalEarnedSeconds,
                totalSpentSeconds = existing.totalSpentSeconds,
                lastUpdatedAt = clock.now().toEpochMilliseconds(),
                syncStatus = syncStatusToString(SyncStatus.SYNCED),
                id = existing.id,
            )
        }
    }

    override fun observeCredit(userId: String): Flow<TimeCredit?> =
        queries.selectTimeCreditByUserId(userId)
            .asFlow()
            .mapToOneOrNull(dispatcher)
            .map { it?.toDomain() }
            .catch { e ->
                throw RepositoryException("Failed to observe credit for user '$userId'", e)
            }
}
