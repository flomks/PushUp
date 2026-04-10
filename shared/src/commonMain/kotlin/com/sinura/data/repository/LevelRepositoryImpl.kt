package com.sinura.data.repository

import com.sinura.data.mapper.toDomain
import com.sinura.db.SinuraDatabase
import com.sinura.domain.model.ExerciseType
import com.sinura.domain.model.LevelCalculator
import com.sinura.domain.model.UserLevel
import com.sinura.domain.repository.LevelRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.datetime.Clock

/**
 * SQLDelight-backed implementation of [LevelRepository].
 *
 * The [UserLevel] table stores only [totalXp]; the current level and progress
 * are derived on every read via [LevelCalculator.fromTotalXp].
 *
 * All suspend functions are main-safe -- dispatcher switching is handled
 * by [safeDbCall].
 *
 * @param database   The SQLDelight-generated [SinuraDatabase] instance.
 * @param dispatcher The [CoroutineDispatcher] used for database I/O.
 * @param clock      Clock used to set [lastUpdatedAt] timestamps.
 */
class LevelRepositoryImpl(
    private val database: SinuraDatabase,
    private val dispatcher: CoroutineDispatcher,
    private val clock: Clock = Clock.System,
) : LevelRepository {

    private val queries get() = database.databaseQueries

    override suspend fun get(userId: String): UserLevel? = safeDbCall(
        dispatcher,
        "Failed to get user level for user '$userId'",
    ) {
        val aggregateXp = ensureAggregateConsistency(userId)
        if (aggregateXp != null) {
            LevelCalculator.fromTotalXp(userId, aggregateXp)
        } else {
            null
        }
    }

    override suspend fun getOrCreate(userId: String): UserLevel = safeDbCall(
        dispatcher,
        "Failed to get or create user level for user '$userId'",
    ) {
        val aggregateXp = ensureAggregateConsistency(userId, createIfMissing = true) ?: 0L
        LevelCalculator.fromTotalXp(userId, aggregateXp)
    }

    override suspend fun addXp(userId: String, xpToAdd: Long): UserLevel {
        require(xpToAdd > 0) { "xpToAdd must be > 0, was $xpToAdd" }
        return safeDbCall(
            dispatcher,
            "Failed to add $xpToAdd XP for user '$userId'",
        ) {
            val now = clock.now().toEpochMilliseconds()
            var newTotalXp = 0L
            database.transaction {
                val existing = queries.selectUserLevelByUserId(userId).executeAsOneOrNull()
                if (existing != null) {
                    newTotalXp = existing.totalXp + xpToAdd
                    queries.updateUserLevelXp(
                        totalXp = newTotalXp,
                        lastUpdatedAt = now,
                        userId = userId,
                    )
                } else {
                    newTotalXp = xpToAdd
                    queries.insertUserLevel(
                        id = userId,
                        userId = userId,
                        totalXp = newTotalXp,
                        lastUpdatedAt = now,
                    )
                }
            }
            LevelCalculator.fromTotalXp(userId, newTotalXp)
        }
    }

    /**
     * Keeps the aggregate [UserLevel] row aligned with the sum of all
     * [ExerciseType]-specific XP rows.
     *
     * Migration rule for legacy users:
     * if no per-exercise rows exist yet but a legacy user-level row has XP,
     * seed that XP into [ExerciseType.PUSH_UPS].
     */
    private fun ensureAggregateConsistency(
        userId: String,
        createIfMissing: Boolean = false,
    ): Long? {
        val existingUserLevel = queries.selectUserLevelByUserId(userId).executeAsOneOrNull()
        val existingExerciseLevels = queries.selectExerciseLevelsByUserId(userId).executeAsList()

        val now = clock.now().toEpochMilliseconds()

        if (existingExerciseLevels.isEmpty() && existingUserLevel != null && existingUserLevel.totalXp > 0L) {
            queries.insertExerciseLevel(
                id = "${userId}_${ExerciseType.PUSH_UPS.id}",
                userId = userId,
                exerciseType = ExerciseType.PUSH_UPS.id,
                totalXp = existingUserLevel.totalXp,
                lastUpdatedAt = now,
            )
        }

        val aggregateXp = queries.selectExerciseLevelsByUserId(userId)
            .executeAsList()
            .sumOf { row -> row.totalXp }

        if (aggregateXp > 0L || createIfMissing) {
            if (existingUserLevel != null) {
                if (existingUserLevel.totalXp != aggregateXp) {
                    queries.updateUserLevelXp(
                        totalXp = aggregateXp,
                        lastUpdatedAt = now,
                        userId = userId,
                    )
                }
            } else {
                queries.insertUserLevel(
                    id = userId,
                    userId = userId,
                    totalXp = aggregateXp,
                    lastUpdatedAt = now,
                )
            }
            return aggregateXp
        }

        return existingUserLevel?.toDomain()?.totalXp
    }
}
