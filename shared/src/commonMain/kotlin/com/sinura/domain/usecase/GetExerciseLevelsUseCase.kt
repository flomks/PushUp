package com.sinura.domain.usecase

import com.sinura.domain.model.ExerciseLevel
import com.sinura.domain.model.ExerciseType
import com.sinura.domain.repository.LevelRepository
import com.sinura.domain.repository.ExerciseLevelRepository

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
    private val levelRepository: LevelRepository,
) {

    /**
     * Returns a list of [ExerciseLevel] for [userId] — one entry per
     * [ExerciseType], ordered by [ExerciseType.ordinal].
     *
     * Exercise types that have never earned XP are returned as level 1 / 0 XP.
     */
    suspend operator fun invoke(userId: String): List<ExerciseLevel> {
        require(userId.isNotBlank()) { "userId must not be blank" }

        var existing = exerciseLevelRepository.getAll(userId)
            .associateBy { it.exerciseType }

        // Legacy migration: if the user only has the old aggregate XP row,
        // seed that history into Push-Ups so total XP becomes the sum of
        // per-activity totals going forward.
        if (existing.isEmpty()) {
            val aggregate = levelRepository.get(userId)
            existing = exerciseLevelRepository.getAll(userId).associateBy { it.exerciseType }
            if (existing.isEmpty() && aggregate != null && aggregate.totalXp > 0L) {
                exerciseLevelRepository.addXp(userId, ExerciseType.PUSH_UPS, aggregate.totalXp)
                existing = exerciseLevelRepository.getAll(userId).associateBy { it.exerciseType }
            }
        }

        return ExerciseType.entries.map { type ->
            existing[type] ?: ExerciseLevel.initial(userId, type)
        }
    }
}
