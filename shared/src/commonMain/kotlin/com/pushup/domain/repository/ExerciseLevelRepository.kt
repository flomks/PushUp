package com.pushup.domain.repository

import com.pushup.domain.model.ExerciseLevel
import com.pushup.domain.model.ExerciseType

/**
 * Repository for reading and updating per-exercise XP / level state.
 *
 * Each (userId, exerciseType) pair has its own XP counter and derived level.
 * Level is computed from [ExerciseLevel.totalXp] using
 * [com.pushup.domain.model.LevelCalculator].
 */
interface ExerciseLevelRepository {

    /**
     * Returns the [ExerciseLevel] for [userId] and [exerciseType], or `null`
     * if no record exists yet.
     */
    suspend fun get(userId: String, exerciseType: ExerciseType): ExerciseLevel?

    /**
     * Returns all [ExerciseLevel] records for [userId] (one per exercise type
     * that has been used at least once).
     */
    suspend fun getAll(userId: String): List<ExerciseLevel>

    /**
     * Returns the [ExerciseLevel] for [userId] and [exerciseType], creating an
     * initial record (level 1, 0 XP) if none exists yet.
     */
    suspend fun getOrCreate(userId: String, exerciseType: ExerciseType): ExerciseLevel

    /**
     * Adds [xpToAdd] to the exercise-specific XP for [userId] and [exerciseType],
     * creating the record if it does not exist.
     *
     * @param userId       The user to award XP to.
     * @param exerciseType The exercise type to award XP for.
     * @param xpToAdd      Amount of XP to add (must be > 0).
     * @return The updated [ExerciseLevel] after the XP has been applied.
     */
    suspend fun addXp(userId: String, exerciseType: ExerciseType, xpToAdd: Long): ExerciseLevel
}
