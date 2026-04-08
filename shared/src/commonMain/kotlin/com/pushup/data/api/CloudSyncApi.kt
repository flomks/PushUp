package com.pushup.data.api

import com.pushup.data.api.dto.CreateJoggingSessionRequest
import com.pushup.data.api.dto.CreateJoggingPlaybackEntryRequest
import com.pushup.data.api.dto.CreateJoggingSegmentRequest
import com.pushup.data.api.dto.CreateRoutePointRequest
import com.pushup.data.api.dto.CreateWorkoutSessionRequest
import com.pushup.data.api.dto.LiveJoggingStatusDTO
import com.pushup.data.api.dto.LiveRunParticipantDTO
import com.pushup.data.api.dto.LiveRunPresenceDTO
import com.pushup.data.api.dto.LiveRunSessionDTO
import com.pushup.data.api.dto.CreateLiveRunParticipantRequest
import com.pushup.data.api.dto.CreateLiveRunSessionRequest
import com.pushup.data.api.dto.CreateRunEventParticipantRequest
import com.pushup.data.api.dto.CreateRunEventRequest
import com.pushup.data.api.dto.RunEventDTO
import com.pushup.data.api.dto.RunEventParticipantDTO
import com.pushup.data.api.dto.SetUsernameRequest
import com.pushup.data.api.dto.UpdateLiveRunParticipantRequest
import com.pushup.data.api.dto.UpdateLiveRunSessionRequest
import com.pushup.data.api.dto.UpdateRunEventParticipantRequest
import com.pushup.data.api.dto.UpdateRunEventRequest
import com.pushup.data.api.dto.UpdateJoggingSessionRequest
import com.pushup.data.api.dto.UpdateTimeCreditRequest
import com.pushup.data.api.dto.UpdateUserProfileRequest
import com.pushup.data.api.dto.UpdateWorkoutSessionRequest
import com.pushup.data.api.dto.UpsertLiveJoggingStatusRequest
import com.pushup.data.api.dto.UpsertLiveRunPresenceRequest
import com.pushup.data.api.dto.UpsertExerciseLevelRequest
import com.pushup.data.api.dto.UpsertUserLevelRequest
import com.pushup.data.api.dto.UsernameCheckResponse
import com.pushup.data.api.dto.UserProfileDTO
import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.JoggingPlaybackEntry
import com.pushup.domain.model.JoggingSegment
import com.pushup.domain.model.RoutePoint
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.model.ExerciseLevel
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

    // =========================================================================
    // ExerciseLevel CRUD
    // =========================================================================

    /**
     * Returns all exercise_levels records for [userId], or an empty list if none exist.
     */
    suspend fun getExerciseLevels(userId: String): List<ExerciseLevel> = emptyList()

    /**
     * Upserts an exercise_levels record for [userId] and exercise type.
     * Creates the row if it does not exist, or updates total_xp if the
     * remote value is lower.
     */
    suspend fun upsertExerciseLevel(
        userId: String,
        request: UpsertExerciseLevelRequest,
    ): ExerciseLevel? = null

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

    // =========================================================================
    // JoggingSession CRUD
    // =========================================================================

    /**
     * Returns all jogging sessions for the authenticated user, newest first.
     */
    suspend fun getJoggingSessions(): List<JoggingSession>

    /**
     * Returns a single jogging session by [id].
     *
     * @throws ApiException.NotFound if no session with [id] exists.
     */
    suspend fun getJoggingSession(id: String): JoggingSession

    /**
     * Creates a new jogging session and returns the server-assigned row.
     */
    suspend fun createJoggingSession(request: CreateJoggingSessionRequest): JoggingSession

    /**
     * Partially updates a jogging session and returns the updated row.
     */
    suspend fun updateJoggingSession(
        id: String,
        request: UpdateJoggingSessionRequest,
    ): JoggingSession

    // =========================================================================
    // RoutePoint CRUD
    // =========================================================================

    /**
     * Returns all route points for [sessionId], ordered by timestamp ascending.
     */
    suspend fun getRoutePoints(sessionId: String): List<RoutePoint>

    /**
     * Bulk-inserts route points in a single request.
     */
    suspend fun createRoutePoints(requests: List<CreateRoutePointRequest>): List<RoutePoint>

    /**
     * Returns all pause/run segments for [sessionId], ordered by start time.
     */
    suspend fun getJoggingSegments(sessionId: String): List<JoggingSegment> {
        return emptyList()
    }

    /**
     * Replaces all segments for [sessionId] with the provided list.
     * Default implementation is a no-op for compatibility with test fakes.
     */
    suspend fun replaceJoggingSegments(
        sessionId: String,
        requests: List<CreateJoggingSegmentRequest>,
    ) {
        // no-op default
    }

    /**
     * Returns all playback timeline entries for [sessionId], ordered by start time.
     */
    suspend fun getJoggingPlaybackEntries(sessionId: String): List<JoggingPlaybackEntry> {
        return emptyList()
    }

    /**
     * Replaces all playback timeline entries for [sessionId] with the provided list.
     * Default implementation is a no-op for compatibility with test fakes.
     */
    suspend fun replaceJoggingPlaybackEntries(
        sessionId: String,
        requests: List<CreateJoggingPlaybackEntryRequest>,
    ) {
        // no-op default
    }

    // =========================================================================
    // User settings (dashboard widget order — same row as credit / privacy settings)
    // =========================================================================

    /**
     * Returns `dashboard_widget_order_json` from `user_settings` for [userId], or `null`.
     */
    suspend fun getUserSettingsDashboardWidgetOrderJson(userId: String): String? = null

    /**
     * PATCHes only `dashboard_widget_order_json` on the `user_settings` row for [userId].
     */
    suspend fun patchUserSettingsDashboardWidgetOrderJson(userId: String, json: String?) {}

    // =========================================================================
    // Live Jogging Status (Presence)
    // =========================================================================

    /**
     * Upserts the live jogging status for the authenticated user.
     * This signals to friends that the user is currently running.
     */
    suspend fun upsertLiveJoggingStatus(request: UpsertLiveJoggingStatusRequest)

    /**
     * Deletes the live jogging status for the authenticated user.
     * This signals that the user has stopped running.
     */
    suspend fun deleteLiveJoggingStatus(userId: String)

    /**
     * Returns the live jogging status for a list of user IDs.
     * Used to check which friends are currently running.
     */
    suspend fun getLiveJoggingStatuses(userIds: List<String>): List<LiveJoggingStatusDTO>

    // =========================================================================
    // Social Running
    // =========================================================================

    suspend fun getRunEvents(): List<RunEventDTO> = emptyList()
    suspend fun getRunEvent(id: String): RunEventDTO? = null
    suspend fun createRunEvent(request: CreateRunEventRequest): RunEventDTO? = null
    suspend fun updateRunEvent(id: String, request: UpdateRunEventRequest): RunEventDTO? = null
    suspend fun deleteRunEvent(id: String) {}
    suspend fun getRunEventParticipants(eventId: String): List<RunEventParticipantDTO> = emptyList()
    suspend fun createRunEventParticipants(requests: List<CreateRunEventParticipantRequest>): List<RunEventParticipantDTO> = emptyList()
    suspend fun updateRunEventParticipant(
        eventId: String,
        userId: String,
        request: UpdateRunEventParticipantRequest,
    ): RunEventParticipantDTO? = null
    suspend fun deleteRunEventParticipant(
        eventId: String,
        userId: String,
    ) {}

    suspend fun getLiveRunSessions(): List<LiveRunSessionDTO> = emptyList()
    suspend fun getLiveRunSession(id: String): LiveRunSessionDTO? = null
    suspend fun createLiveRunSession(request: CreateLiveRunSessionRequest): LiveRunSessionDTO? = null
    suspend fun updateLiveRunSession(id: String, request: UpdateLiveRunSessionRequest): LiveRunSessionDTO? = null
    suspend fun getLiveRunParticipants(sessionId: String): List<LiveRunParticipantDTO> = emptyList()
    suspend fun createLiveRunParticipants(requests: List<CreateLiveRunParticipantRequest>): List<LiveRunParticipantDTO> = emptyList()
    suspend fun updateLiveRunParticipant(
        sessionId: String,
        userId: String,
        request: UpdateLiveRunParticipantRequest,
    ): LiveRunParticipantDTO? = null
    suspend fun getLiveRunPresence(sessionId: String): List<LiveRunPresenceDTO> = emptyList()
    suspend fun upsertLiveRunPresence(request: UpsertLiveRunPresenceRequest): LiveRunPresenceDTO? = null
}
