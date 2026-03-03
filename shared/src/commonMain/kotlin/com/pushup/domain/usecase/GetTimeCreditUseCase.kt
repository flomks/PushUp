package com.pushup.domain.usecase

import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.repository.TimeCreditRepository
import kotlinx.datetime.Clock

/**
 * Use-case: Retrieve the current time-credit balance for a user.
 *
 * Returns the user's [TimeCredit] record containing total earned seconds,
 * total spent seconds, and the derived available balance.
 *
 * If no credit record exists yet (e.g. a brand-new user who has not completed
 * any workout), an empty [TimeCredit] with all values at zero is created,
 * persisted, and returned.
 *
 * @property timeCreditRepository Repository for reading and creating credit records.
 * @property clock Clock used to timestamp newly created credit records.
 */
class GetTimeCreditUseCase(
    private val timeCreditRepository: TimeCreditRepository,
    private val clock: Clock = Clock.System,
) {

    /**
     * Returns the time-credit balance for the given [userId].
     *
     * @param userId The ID of the user whose credits to retrieve.
     * @return The user's [TimeCredit], creating an empty record if none exists.
     */
    suspend operator fun invoke(userId: String): TimeCredit {
        require(userId.isNotBlank()) { "userId must not be blank" }

        val existing = timeCreditRepository.get(userId)
        if (existing != null) return existing

        // No record yet -- create and persist an empty one
        val empty = TimeCredit(
            userId = userId,
            totalEarnedSeconds = 0L,
            totalSpentSeconds = 0L,
            lastUpdatedAt = clock.now(),
            syncStatus = SyncStatus.PENDING,
        )
        timeCreditRepository.update(empty)
        return empty
    }
}
