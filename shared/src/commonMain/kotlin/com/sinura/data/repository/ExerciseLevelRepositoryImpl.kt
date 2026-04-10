package com.sinura.data.repository

import com.sinura.data.mapper.toDomain
import com.sinura.db.SinuraDatabase
import com.sinura.domain.model.ExerciseLevel
import com.sinura.domain.model.ExerciseType
import com.sinura.domain.model.LevelCalculator
import com.sinura.domain.repository.ExerciseLevelRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.datetime.Clock

/**
 * SQLDelight-backed implementation of [ExerciseLevelRepository].
 *
 * Stores only [totalXp] per (userId, exerciseType); the level and progress
 * are derived on every read via [LevelCalculator.exerciseLevelFromTotalXp].
 *
 * @param database   The SQLDelight-generated [SinuraDatabase] instance.
 * @param dispatcher The [CoroutineDispatcher] used for database I/O.
 * @param clock      Clock used to set [lastUpdatedAt] timestamps.
 */
class ExerciseLevelRepositoryImpl(
    private val database: SinuraDatabase,
    private val dispatcher: CoroutineDispatcher,
    private val clock: Clock = Clock.System,
) : ExerciseLevelRepository {

    private val queries get() = database.databaseQueries

    override suspend fun get(
        userId: String,
        exerciseType: ExerciseType,
    ): ExerciseLevel? = safeDbCall(
        dispatcher,
        "Failed to get exercise level for user '$userId', type '${exerciseType.id}'",
    ) {
        queries.selectExerciseLevelByUserIdAndType(userId, exerciseType.id)
            .executeAsOneOrNull()
            ?.toDomain()
    }

    override suspend fun getAll(userId: String): List<ExerciseLevel> = safeDbCall(
        dispatcher,
        "Failed to get exercise levels for user '$userId'",
    ) {
        queries.selectExerciseLevelsByUserId(userId)
            .executeAsList()
            .map { it.toDomain() }
    }

    override suspend fun getOrCreate(
        userId: String,
        exerciseType: ExerciseType,
    ): ExerciseLevel = safeDbCall(
        dispatcher,
        "Failed to get or create exercise level for user '$userId', type '${exerciseType.id}'",
    ) {
        val existing = queries.selectExerciseLevelByUserIdAndType(userId, exerciseType.id)
            .executeAsOneOrNull()
        if (existing != null) {
            existing.toDomain()
        } else {
            val now = clock.now().toEpochMilliseconds()
            queries.insertExerciseLevel(
                id = "${userId}_${exerciseType.id}",
                userId = userId,
                exerciseType = exerciseType.id,
                totalXp = 0L,
                lastUpdatedAt = now,
            )
            ExerciseLevel.initial(userId, exerciseType)
        }
    }

    override suspend fun addXp(
        userId: String,
        exerciseType: ExerciseType,
        xpToAdd: Long,
    ): ExerciseLevel {
        require(xpToAdd > 0) { "xpToAdd must be > 0, was $xpToAdd" }
        return safeDbCall(
            dispatcher,
            "Failed to add $xpToAdd XP for user '$userId', type '${exerciseType.id}'",
        ) {
            val now = clock.now().toEpochMilliseconds()
            var newTotalXp = 0L
            database.transaction {
                val existing = queries.selectExerciseLevelByUserIdAndType(userId, exerciseType.id)
                    .executeAsOneOrNull()
                if (existing != null) {
                    newTotalXp = existing.totalXp + xpToAdd
                    queries.updateExerciseLevelXp(
                        totalXp = newTotalXp,
                        lastUpdatedAt = now,
                        userId = userId,
                        exerciseType = exerciseType.id,
                    )
                } else {
                    newTotalXp = xpToAdd
                    queries.insertExerciseLevel(
                        id = "${userId}_${exerciseType.id}",
                        userId = userId,
                        exerciseType = exerciseType.id,
                        totalXp = newTotalXp,
                        lastUpdatedAt = now,
                    )
                }
            }
            LevelCalculator.exerciseLevelFromTotalXp(userId, exerciseType, newTotalXp)
        }
    }
}
