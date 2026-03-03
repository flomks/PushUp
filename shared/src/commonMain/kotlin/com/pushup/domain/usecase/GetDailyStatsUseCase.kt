package com.pushup.domain.usecase

import com.pushup.domain.model.DailyStats
import com.pushup.domain.repository.StatsRepository
import kotlinx.datetime.LocalDate

/**
 * Use-case: Retrieve aggregated workout statistics for a single day.
 *
 * Delegates to [StatsRepository.getDailyStats] and returns `null` when
 * no workout data exists for the requested date.
 *
 * @property statsRepository Repository used to retrieve daily statistics.
 */
class GetDailyStatsUseCase(
    private val statsRepository: StatsRepository,
) {

    /**
     * Returns the daily statistics for [userId] on [date].
     *
     * @param userId The ID of the user whose stats to retrieve.
     * @param date The calendar date to aggregate.
     * @return [DailyStats] for the given day, or `null` if no data exists.
     */
    suspend operator fun invoke(userId: String, date: LocalDate): DailyStats? {
        require(userId.isNotBlank()) { "userId must not be blank" }
        return statsRepository.getDailyStats(userId, date)
    }
}
