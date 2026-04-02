package com.pushup.domain.usecase

import com.pushup.domain.model.MonthlyActivitySummary
import com.pushup.domain.repository.ActivityStatsRepository

/**
 * Returns unified monthly activity data across all workout types,
 * suitable for rendering a heatmap grid.
 */
class GetMonthlyActivityUseCase(
    private val activityStatsRepository: ActivityStatsRepository,
) {
    suspend operator fun invoke(
        userId: String,
        month: Int,
        year: Int,
    ): MonthlyActivitySummary =
        activityStatsRepository.getMonthlyActivity(userId, month, year)
}
