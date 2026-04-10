package com.sinura.domain.usecase

import com.sinura.domain.model.SyncStatus
import com.sinura.domain.model.TimeCredit
import com.sinura.domain.repository.TimeCreditRepository
import kotlinx.datetime.Clock

/**
 * Use-case: Retrieve the current time-credit balance for a user.
 *
 * Returns the user's [TimeCredit] record containing total earned seconds,
 * total spent seconds, and the derived available balance.
 *
 * If a daily reset is due (checked via [ApplyDailyResetUseCase]), it is
 * applied before returning the credit.
 *
 * If no credit record exists yet (e.g. a brand-new user who has not completed
 * any workout), an empty [TimeCredit] with all values at zero is created,
 * persisted, and returned.
 *
 * @property timeCreditRepository Repository for reading and creating credit records.
 * @property applyDailyResetUseCase Use-case for applying the daily credit reset.
 * @property clock Clock used to timestamp newly created credit records.
 */
class GetTimeCreditUseCase(
    private val timeCreditRepository: TimeCreditRepository,
    private val applyDailyResetUseCase: ApplyDailyResetUseCase? = null,
    private val clock: Clock = Clock.System,
) {

    /**
     * Returns the time-credit balance for the given [userId].
     *
     * Applies the daily reset if one is due before returning the credit.
     *
     * @param userId The ID of the user whose credits to retrieve.
     * @return The user's [TimeCredit], creating an empty record if none exists.
     */
    suspend operator fun invoke(userId: String): TimeCredit {
        require(userId.isNotBlank()) { "userId must not be blank" }

        // Try to apply the daily reset first (if the use-case is wired up).
        val afterReset = applyDailyResetUseCase?.invoke(userId)
        if (afterReset != null) return afterReset

        // Fallback: read directly from the repository.
        val existing = timeCreditRepository.get(userId)
        if (existing != null) return existing

        // No record yet -- create and persist an empty one
        val empty = TimeCredit(
            userId = userId,
            totalEarnedSeconds = 0L,
            totalSpentSeconds = 0L,
            dailyEarnedSeconds = 0L,
            dailySpentSeconds = 0L,
            lastResetAt = null,
            lastUpdatedAt = clock.now(),
            syncStatus = SyncStatus.PENDING,
        )
        timeCreditRepository.update(empty)
        return empty
    }
}
