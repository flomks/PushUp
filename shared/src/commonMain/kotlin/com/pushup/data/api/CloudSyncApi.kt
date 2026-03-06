package com.pushup.data.api

import com.pushup.data.api.dto.CreateWorkoutSessionRequest
import com.pushup.data.api.dto.UpdateTimeCreditRequest
import com.pushup.data.api.dto.UpdateWorkoutSessionRequest
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.model.WorkoutSession

/**
 * Abstraction over the remote cloud API operations required by the sync use-cases.
 *
 * This interface is a subset of [SupabaseClient]'s public API, exposing only the
 * operations needed for offline-first synchronisation:
 * - Fetching all workout sessions for the authenticated user.
 * - Fetching a single workout session by ID.
 * - Creating a new workout session.
 * - Updating an existing workout session.
 * - Fetching the time-credit record for a user.
 * - Updating the time-credit record for a user.
 *
 * Introducing this interface allows the sync use-cases to be tested with a
 * fake implementation without requiring a real [SupabaseClient] (which is a
 * final class backed by a real HTTP client).
 *
 * [SupabaseClient] implements this interface directly.
 */
interface CloudSyncApi {

    /**
     * Returns all workout sessions for the authenticated user, newest first.
     */
    suspend fun getWorkoutSessions(): List<WorkoutSession>

    /**
     * Returns a single workout session by [id].
     *
     * @throws ApiException.NotFound if no session with [id] exists.
     */
    suspend fun getWorkoutSession(id: String): WorkoutSession

    /**
     * Creates a new workout session and returns the server-assigned row.
     */
    suspend fun createWorkoutSession(request: CreateWorkoutSessionRequest): WorkoutSession

    /**
     * Partially updates a workout session and returns the updated row.
     *
     * @throws ApiException.NotFound if no session with [id] exists.
     */
    suspend fun updateWorkoutSession(
        id: String,
        request: UpdateWorkoutSessionRequest,
    ): WorkoutSession

    /**
     * Returns the time credit record for [userId], or `null` if none exists yet.
     */
    suspend fun getTimeCredit(userId: String): TimeCredit?

    /**
     * Partially updates the time credit record for [userId] and returns the updated row.
     *
     * @throws ApiException.NotFound if no time credit record exists for [userId].
     */
    suspend fun updateTimeCredit(
        userId: String,
        request: UpdateTimeCreditRequest,
    ): TimeCredit
}
