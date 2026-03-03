package com.pushup.domain.usecase

import com.pushup.domain.model.TotalStats
import com.pushup.domain.repository.StatsRepository

/**
 * Use-case: Retrieve lifetime aggregated workout statistics for a user.
 *
 * Delegates to [StatsRepository.getTotalStats] and returns `null` when
 * the user has no workout data at all.
 *
 * @property statsRepository Repository used to retrieve total statistics.
 */
class GetTotalStatsUseCase(
    private val statsRepository: StatsRepository,
) {

    /**
     * Returns the lifetime statistics for [userId].
     *
     * @param userId The ID of the user whose total stats to retrieve.
     * @return [TotalStats] aggregated across all time, or `null` if no data exists.
     */
    suspend operator fun invoke(userId: String): TotalStats? {
        require(userId.isNotBlank()) { "userId must not be blank" }
        return statsRepository.getTotalStats(userId)
    }
}
