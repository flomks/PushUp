package com.pushup.domain.usecase

import com.pushup.domain.model.MonthlyStats
import com.pushup.domain.repository.StatsRepository

/**
 * Use-case: Retrieve aggregated workout statistics for a calendar month.
 *
 * Delegates to [StatsRepository.getMonthlyStats] and returns `null` when
 * no workout data exists for the requested month.
 *
 * @property statsRepository Repository used to retrieve monthly statistics.
 */
class GetMonthlyStatsUseCase(
    private val statsRepository: StatsRepository,
) {

    /**
     * Returns the monthly statistics for [userId] in the given [month] and [year].
     *
     * @param userId The ID of the user whose stats to retrieve.
     * @param month The month number (1-12).
     * @param year The four-digit year.
     * @return [MonthlyStats] for the given month, or `null` if no data exists.
     * @throws IllegalArgumentException if [month] is not in 1..12.
     */
    suspend operator fun invoke(userId: String, month: Int, year: Int): MonthlyStats? {
        require(userId.isNotBlank()) { "userId must not be blank" }
        require(month in 1..12) { "month must be in [1, 12], was $month" }
        require(year > 0) { "year must be > 0, was $year" }
        return statsRepository.getMonthlyStats(userId, month, year)
    }
}
