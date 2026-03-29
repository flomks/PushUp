package com.pushup.domain.model

import kotlinx.serialization.Serializable

/**
 * Represents the current XP / level state for a specific [exerciseType] of a user.
 *
 * Uses the same level curve as [UserLevel] (see [LevelCalculator.xpRequiredForLevel]).
 *
 * @property userId              Identifier of the user this record belongs to.
 * @property exerciseType        The exercise this level tracks.
 * @property totalXp             Total XP accumulated for this exercise across all time.
 * @property level               Current level for this exercise (1-based).
 * @property xpIntoLevel         XP accumulated within the current level.
 * @property xpRequiredForNextLevel XP needed to advance to the next level.
 */
@Serializable
data class ExerciseLevel(
    val userId: String,
    val exerciseType: ExerciseType,
    val totalXp: Long,
    val level: Int,
    val xpIntoLevel: Long,
    val xpRequiredForNextLevel: Long,
) {
    init {
        require(userId.isNotBlank()) { "ExerciseLevel.userId must not be blank" }
        require(totalXp >= 0) { "ExerciseLevel.totalXp must be >= 0, was $totalXp" }
        require(level >= 1) { "ExerciseLevel.level must be >= 1, was $level" }
        require(xpIntoLevel >= 0) { "ExerciseLevel.xpIntoLevel must be >= 0, was $xpIntoLevel" }
        require(xpRequiredForNextLevel > 0) {
            "ExerciseLevel.xpRequiredForNextLevel must be > 0, was $xpRequiredForNextLevel"
        }
        require(xpIntoLevel < xpRequiredForNextLevel) {
            "ExerciseLevel.xpIntoLevel ($xpIntoLevel) must be < xpRequiredForNextLevel ($xpRequiredForNextLevel)"
        }
    }

    /**
     * Progress fraction within the current level, in [0.0, 1.0).
     */
    val levelProgress: Float
        get() = xpIntoLevel.toFloat() / xpRequiredForNextLevel.toFloat()

    companion object {
        /**
         * Creates an initial [ExerciseLevel] with zero XP.
         */
        fun initial(userId: String, exerciseType: ExerciseType): ExerciseLevel =
            LevelCalculator.exerciseLevelFromTotalXp(userId, exerciseType, 0L)
    }
}
