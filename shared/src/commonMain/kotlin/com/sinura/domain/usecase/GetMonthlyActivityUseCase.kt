package com.sinura.domain.usecase

import com.sinura.domain.model.MonthlyActivitySummary
import com.sinura.domain.repository.ActivityStatsRepository

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
