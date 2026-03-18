package com.pushup.domain.usecase

import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.repository.TimeCreditRepository
import kotlinx.datetime.Clock

/**
 * Use-case: Spend (deduct) time-credit seconds from a user's balance.
 *
 * This use-case is called by the Screen-Time controller when the user consumes
 * screen time. It verifies that sufficient credits are available before deducting.
 *
 * Spending deducts from both the all-time total and the daily balance.
 *
 * Returns a [SpendResult] that is either [SpendResult.Success] (with the updated
 * [TimeCredit]) or [SpendResult.InsufficientCredits] (with the current balance).
 * The use-case never throws for an insufficient-balance condition -- callers
 * should inspect the result type instead.
 *
 * @property timeCreditRepository Repository for reading and updating credit records.
 * @property clock Clock used to timestamp newly created credit records.
 */
class SpendTimeCreditUseCase(
    private val timeCreditRepository: TimeCreditRepository,
    private val clock: Clock = Clock.System,
) {

    /**
     * Attempts to spend [secondsToSpend] from the user's credit balance.
     *
     * @param userId The ID of the user whose credits to deduct.
     * @param secondsToSpend The number of seconds to spend (must be > 0).
     * @return [SpendResult.Success] with the updated balance, or
     *   [SpendResult.InsufficientCredits] if the balance is too low.
     * @throws IllegalArgumentException if [userId] is blank or [secondsToSpend] is not positive.
     */
    suspend operator fun invoke(userId: String, secondsToSpend: Long): SpendResult {
        require(userId.isNotBlank()) { "userId must not be blank" }
        require(secondsToSpend > 0) { "secondsToSpend must be > 0, was $secondsToSpend" }

        // Ensure a credit record exists; create an empty one if not.
        val current = timeCreditRepository.get(userId)
            ?: run {
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
                empty
            }

        if (current.availableSeconds < secondsToSpend) {
            return SpendResult.InsufficientCredits(current)
        }

        timeCreditRepository.addSpentSeconds(userId, secondsToSpend)

        // Build the updated credit locally to avoid an extra DB round-trip.
        // The new balance is deterministic: addSpentSeconds is an atomic increment
        // on both totalSpentSeconds and dailySpentSeconds.
        // syncStatus is explicitly set to PENDING to match the DB state written by
        // addSpentSeconds -- the previous status may have been SYNCED.
        val updated = current.copy(
            totalSpentSeconds = current.totalSpentSeconds + secondsToSpend,
            dailySpentSeconds = current.dailySpentSeconds + secondsToSpend,
            lastUpdatedAt = clock.now(),
            syncStatus = SyncStatus.PENDING,
        )
        return SpendResult.Success(updated)
    }
}

/**
 * Result of a [SpendTimeCreditUseCase] invocation.
 */
sealed class SpendResult {

    /**
     * The spend was successful.
     *
     * @property credit The updated [TimeCredit] after deducting the spent seconds.
     */
    data class Success(val credit: TimeCredit) : SpendResult()

    /**
     * The spend failed because the user does not have enough available credits.
     *
     * @property credit The current [TimeCredit] showing the actual balance.
     */
    data class InsufficientCredits(val credit: TimeCredit) : SpendResult()
}
