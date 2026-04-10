package com.sinura.data.mapper

import com.sinura.db.ExerciseLevel as DbExerciseLevel
import com.sinura.db.UserLevel as DbUserLevel
import com.sinura.domain.model.ExerciseLevel
import com.sinura.domain.model.ExerciseType
import com.sinura.domain.model.LevelCalculator
import com.sinura.domain.model.UserLevel

/**
 * Converts a SQLDelight [DbUserLevel] row to a domain [UserLevel] by
 * deriving the current level and progress from [DbUserLevel.totalXp].
 */
fun DbUserLevel.toDomain(): UserLevel = LevelCalculator.fromTotalXp(
    userId = userId,
    totalXp = totalXp,
)

/**
 * Converts a SQLDelight [DbExerciseLevel] row to a domain [ExerciseLevel] by
 * deriving the current level and progress from [DbExerciseLevel.totalXp].
 */
fun DbExerciseLevel.toDomain(): ExerciseLevel = LevelCalculator.exerciseLevelFromTotalXp(
    userId = userId,
    exerciseType = ExerciseType.fromId(exerciseType),
    totalXp = totalXp,
)
