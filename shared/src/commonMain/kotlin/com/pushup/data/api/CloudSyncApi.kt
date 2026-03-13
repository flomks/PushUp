package com.pushup.data.api

import com.pushup.data.api.dto.CreateWorkoutSessionRequest
import com.pushup.data.api.dto.SetUsernameRequest
import com.pushup.data.api.dto.UpdateTimeCreditRequest
import com.pushup.data.api.dto.UpdateUserProfileRequest
import com.pushup.data.api.dto.UpdateWorkoutSessionRequest
import com.pushup.data.api.dto.UpsertUserLevelRequest
import com.pushup.data.api.dto.UsernameCheckResponse
import com.pushup.data.api.dto.UserProfileDTO
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.model.UserLevel
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

    /**
     * Returns the user profile (display name, email) for [userId] from Supabase,
     * or `null` if no profile row exists yet.
     */
    suspend fun getUserProfile(userId: String): UserProfileDTO?

    /**
     * Updates the display name for [userId] in the Supabase public.users table.
     *
     * @throws ApiException.NotFound if no user row exists for [userId].
     */
    suspend fun updateUserProfile(
        userId: String,
        request: UpdateUserProfileRequest,
    ): UserProfileDTO

    /**
     * Returns the user_levels record for [userId], or `null` if none exists yet.
     */
    suspend fun getUserLevel(userId: String): UserLevel?

    /**
     * Upserts the user_levels record for [userId] with the given [request].
     *
     * Creates the row if it does not exist, or updates [total_xp] if the
     * remote value is lower than the local value (local wins on conflict).
     */
    suspend fun upsertUserLevel(
        userId: String,
        request: UpsertUserLevelRequest,
    ): UserLevel

    /**
     * Checks whether [username] is available (not taken by another user).
     *
     * @return [UsernameCheckResponse] with [available] = true if the username
     *         is free to use, false if it is already taken.
     */
    suspend fun checkUsernameAvailability(username: String): UsernameCheckResponse

    /**
     * Sets the username for the currently authenticated user.
     *
     * @throws ApiException if the username is taken or invalid.
     */
    suspend fun setUsername(request: SetUsernameRequest): String
}
