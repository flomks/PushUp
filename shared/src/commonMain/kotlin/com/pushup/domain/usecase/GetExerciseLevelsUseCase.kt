package com.pushup.domain.usecase

import com.pushup.domain.model.ExerciseLevel
import com.pushup.domain.model.ExerciseType
import com.pushup.domain.repository.ExerciseLevelRepository

/**
 * Use-case: Retrieve the per-exercise XP / level state for a user.
 *
 * Returns one [ExerciseLevel] for every [ExerciseType], creating initial
 * (level 1, 0 XP) records for any exercise types that have never been used.
 *
 * @property exerciseLevelRepository Repository used to read and initialise
 *   exercise-level data.
 */
class GetExerciseLevelsUseCase(
    private val exerciseLevelRepository: ExerciseLevelRepository,
) {

    /**
     * Returns a list of [ExerciseLevel] for [userId] — one entry per
     * [ExerciseType], ordered by [ExerciseType.ordinal].
     *
     * Exercise types that have never earned XP are returned as level 1 / 0 XP.
     */
    suspend operator fun invoke(userId: String): List<ExerciseLevel> {
        require(userId.isNotBlank()) { "userId must not be blank" }

        val existing = exerciseLevelRepository.getAll(userId)
            .associateBy { it.exerciseType }

        return ExerciseType.entries.map { type ->
            existing[type] ?: ExerciseLevel.initial(userId, type)
        }
    }
}
