package com.pushup.data.mapper

import com.pushup.db.UserLevel as DbUserLevel
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
