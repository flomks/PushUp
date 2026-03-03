package com.pushup.domain.repository

import com.pushup.domain.model.TimeCredit
import kotlinx.coroutines.flow.Flow

/**
 * Repository for managing [TimeCredit] entities.
 *
 * Provides read and write access to a user's accumulated screen-time credits,
 * including incremental earn/spend operations and synchronization tracking.
 *
 * Implementations must be **main-safe** -- all dispatcher switching is handled internally.
 */
interface TimeCreditRepository {

    /**
     * Retrieves the current time-credit balance for the given [userId].
     *
     * @param userId The user whose credit balance to retrieve.
     * @return The time credit, or `null` if no record exists for this user.
     */
    suspend fun get(userId: String): TimeCredit?

    /**
     * Replaces the entire time-credit record for the user identified by [credit]'s userId.
     *
     * @param credit The updated time-credit state to persist.
     */
    suspend fun update(credit: TimeCredit)

    /**
     * Atomically adds earned screen-time seconds to the user's credit balance.
     *
     * @param userId The user whose credits to increase.
     * @param seconds The number of seconds earned (must be > 0).
     */
    suspend fun addEarnedSeconds(userId: String, seconds: Long)

    /**
     * Atomically adds spent screen-time seconds to the user's credit balance.
     *
     * @param userId The user whose credits to decrease.
     * @param seconds The number of seconds spent (must be > 0).
     */
    suspend fun addSpentSeconds(userId: String, seconds: Long)

    /**
     * Marks the time-credit record for the given [userId] as successfully synced.
     *
     * @param userId The user whose credit sync status to update.
     */
    suspend fun markAsSynced(userId: String)

    /**
     * Observes the time-credit balance for the given [userId] as a reactive [Flow].
     *
     * @param userId The user whose credits to observe.
     */
    fun observeCredit(userId: String): Flow<TimeCredit?>
}
