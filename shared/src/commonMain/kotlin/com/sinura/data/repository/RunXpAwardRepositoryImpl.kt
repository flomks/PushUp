package com.sinura.data.repository

import com.sinura.db.SinuraDatabase
import com.sinura.db.RunXpAward as DbRunXpAward
import com.sinura.domain.model.RunXpAward
import com.sinura.domain.model.RunXpBonusType
import com.sinura.domain.repository.RunXpAwardRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.datetime.Instant

class RunXpAwardRepositoryImpl(
    private val database: SinuraDatabase,
    private val dispatcher: CoroutineDispatcher,
) : RunXpAwardRepository {

    private val queries get() = database.databaseQueries

    override suspend fun save(award: RunXpAward): RunXpAward = safeDbCall(
        dispatcher,
        "Failed to save run XP award '${award.id}'",
    ) {
        val existing = queries.selectRunXpAwardBySessionIdAndUserId(award.sessionId, award.userId).executeAsOneOrNull()
        if (existing != null) {
            return@safeDbCall existing.toDomain()
        }
        queries.insertRunXpAward(
            id = award.id,
            userId = award.userId,
            sessionId = award.sessionId,
            baseXp = award.baseXp,
            bonusType = award.bonusType.toDbValue(),
            bonusMultiplier = award.bonusMultiplier,
            bonusXp = award.bonusXp,
            totalXpAwarded = award.totalXpAwarded,
            awardedAt = award.awardedAt.toEpochMilliseconds(),
            createdAt = award.awardedAt.toEpochMilliseconds(),
            updatedAt = award.awardedAt.toEpochMilliseconds(),
        )
        award
    }

    override suspend fun getBySessionIdAndUserId(sessionId: String, userId: String): RunXpAward? = safeDbCall(
        dispatcher,
        "Failed to get run XP award for session '$sessionId' and user '$userId'",
    ) {
        queries.selectRunXpAwardBySessionIdAndUserId(sessionId, userId).executeAsOneOrNull()?.toDomain()
    }

    override suspend fun getBySessionId(sessionId: String): List<RunXpAward> = safeDbCall(
        dispatcher,
        "Failed to get run XP awards for session '$sessionId'",
    ) {
        queries.selectRunXpAwardsBySessionId(sessionId).executeAsList().map { it.toDomain() }
    }

    override suspend fun getByUserId(userId: String): List<RunXpAward> = safeDbCall(
        dispatcher,
        "Failed to get run XP awards for user '$userId'",
    ) {
        queries.selectRunXpAwardsByUserId(userId).executeAsList().map { it.toDomain() }
    }
}

private fun DbRunXpAward.toDomain(): RunXpAward = RunXpAward(
    id = id,
    userId = userId,
    sessionId = sessionId,
    baseXp = baseXp,
    bonusType = RunXpBonusType.valueOf(bonusType.uppercase()),
    bonusMultiplier = bonusMultiplier,
    bonusXp = bonusXp,
    totalXpAwarded = totalXpAwarded,
    awardedAt = Instant.fromEpochMilliseconds(awardedAt),
)

private fun RunXpBonusType.toDbValue(): String = name.lowercase()
