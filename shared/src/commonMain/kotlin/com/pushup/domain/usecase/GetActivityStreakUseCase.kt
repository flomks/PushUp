package com.pushup.domain.usecase

import com.pushup.domain.repository.ActivityStatsRepository

/**
 * Returns the unified activity streak (current, longest) calculated
 * from all workout types — not just push-ups.
 */
class GetActivityStreakUseCase(
    private val activityStatsRepository: ActivityStatsRepository,
) {
    /**
     * @return Pair of (currentStreakDays, longestStreakDays).
     */
    suspend operator fun invoke(userId: String): Pair<Int, Int> =
        activityStatsRepository.getActivityStreak(userId)
}
