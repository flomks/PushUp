package com.sinura.domain.usecase

import com.sinura.domain.model.WeeklyStats
import com.sinura.domain.repository.StatsRepository
import kotlinx.datetime.LocalDate

/**
 * Use-case: Retrieve aggregated workout statistics for a calendar week.
 *
 * Delegates to [StatsRepository.getWeeklyStats] and returns `null` when
 * no workout data exists for the requested week.
 *
 * @property statsRepository Repository used to retrieve weekly statistics.
 */
class GetWeeklyStatsUseCase(
    private val statsRepository: StatsRepository,
) {

    /**
     * Returns the weekly statistics for [userId] starting on [weekStartDate].
     *
     * @param userId The ID of the user whose stats to retrieve.
     * @param weekStartDate The first day (typically Monday) of the week to aggregate.
     * @return [WeeklyStats] for the given week, or `null` if no data exists.
     */
    suspend operator fun invoke(userId: String, weekStartDate: LocalDate): WeeklyStats? {
        require(userId.isNotBlank()) { "userId must not be blank" }
        return statsRepository.getWeeklyStats(userId, weekStartDate)
    }
}
