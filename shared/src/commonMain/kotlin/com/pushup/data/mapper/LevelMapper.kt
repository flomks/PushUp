package com.pushup.data.mapper

import com.pushup.db.ExerciseLevel as DbExerciseLevel
import com.pushup.db.UserLevel as DbUserLevel
import com.pushup.domain.model.ExerciseLevel
import com.pushup.domain.model.ExerciseType
import com.pushup.domain.model.LevelCalculator
import com.pushup.domain.model.UserLevel

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
