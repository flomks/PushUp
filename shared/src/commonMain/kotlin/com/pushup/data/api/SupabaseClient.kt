package com.pushup.data.api

import com.pushup.data.api.dto.CreateJoggingSessionRequest
import com.pushup.data.api.dto.CreateJoggingPlaybackEntryRequest
import com.pushup.data.api.dto.CreateJoggingSegmentRequest
import com.pushup.data.api.dto.CreateLiveRunParticipantRequest
import com.pushup.data.api.dto.CreateLiveRunSessionRequest
import com.pushup.data.api.dto.CreatePushUpRecordRequest
import com.pushup.data.api.dto.CreateRoutePointRequest
import com.pushup.data.api.dto.CreateRunEventParticipantRequest
import com.pushup.data.api.dto.CreateRunEventRequest
import com.pushup.data.api.dto.CreateWorkoutSessionRequest
import com.pushup.data.api.dto.JoggingSessionDTO
import com.pushup.data.api.dto.JoggingPlaybackEntryDTO
import com.pushup.data.api.dto.JoggingSegmentDTO
import com.pushup.data.api.dto.LiveRunParticipantDTO
import com.pushup.data.api.dto.LiveRunPresenceDTO
import com.pushup.data.api.dto.LiveRunSessionDTO
import com.pushup.data.api.dto.LiveJoggingStatusDTO
import com.pushup.data.api.dto.PushUpRecordDTO
import com.pushup.data.api.dto.RoutePointDTO
import com.pushup.data.api.dto.RunEventDTO
import com.pushup.data.api.dto.RunEventParticipantDTO
import com.pushup.data.api.dto.SetUsernameRequest
import com.pushup.data.api.dto.TimeCreditDTO
import com.pushup.data.api.dto.UpdateLiveRunParticipantRequest
import com.pushup.data.api.dto.UpdateLiveRunSessionRequest
import com.pushup.data.api.dto.UpdateJoggingSessionRequest
import com.pushup.data.api.dto.UpdateRunEventParticipantRequest
import com.pushup.data.api.dto.UpdateRunEventRequest
import com.pushup.data.api.dto.UpdateTimeCreditRequest
import com.pushup.data.api.dto.UpdateUserProfileRequest
import com.pushup.data.api.dto.UpdateWorkoutSessionRequest
import com.pushup.data.api.dto.UpsertLiveJoggingStatusRequest
import com.pushup.data.api.dto.UpsertLiveRunPresenceRequest
import com.pushup.data.api.dto.ExerciseLevelDTO
import com.pushup.data.api.dto.UpsertExerciseLevelRequest
import com.pushup.data.api.dto.UpsertUserLevelRequest
import com.pushup.data.api.dto.UserLevelDTO
import com.pushup.data.api.dto.UserProfileDTO
import com.pushup.data.api.dto.UserSettingsCloudRowDTO
import com.pushup.data.api.dto.UsernameCheckResponse
import com.pushup.data.api.dto.WorkoutSessionDTO
import com.pushup.data.api.dto.toDomain
import com.pushup.domain.model.ExerciseLevel
import com.pushup.domain.model.ExerciseType
import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.JoggingPlaybackEntry
import com.pushup.domain.model.JoggingSegment
import com.pushup.domain.model.LevelCalculator
import com.pushup.domain.model.PushUpRecord
import com.pushup.domain.model.RoutePoint
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.model.UserLevel
import com.pushup.domain.model.WorkoutSession
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.patch
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/**
 * Wrapper around the Supabase PostgREST REST API for CRUD operations on
 * [WorkoutSession], [PushUpRecord], and [TimeCredit].
 *
 * ## Authentication
 * Every request includes two headers:
 * - `apikey`: the Supabase publishable key (required for all PostgREST requests)
 * - `Authorization: Bearer <jwt>`: the user's JWT (required for RLS-protected tables)
 *
 * The JWT is fetched lazily on every request via [tokenProvider] so it is always
 * fresh (Supabase tokens expire after 1 hour by default).
 *
 * ## Error handling
 * All HTTP and network errors are mapped to [ApiException] subclasses before
 * propagating to callers. Transient errors are retried automatically up to
 * [maxRetries] times with exponential back-off (see [ApiClientBase.withRetry]).
 *
 * ## Supabase PostgREST conventions used
 * - Filter by column: `?column=eq.<value>`
 * - Ordering: `?order=column.desc`
 * - `Prefer: return=representation` on POST/PATCH to get the created/updated row back
 *
 * @property httpClient             Configured [HttpClient] (from [createHttpClient]).
 * @property supabaseUrl            Supabase project base URL, e.g. `https://<ref>.supabase.co`.
 * @property supabasePublishableKey Supabase publishable (public) API key.
 *                                  Previously called the "anon key".
 * @property tokenProvider          Returns the current JWT access token (called on every request).
 * @property clock                  Used for timestamp fallbacks when the server omits `updated_at`.
 * @property maxRetries             Max retry attempts for transient errors (default 3).
 */
class SupabaseClient(
    private val httpClient: HttpClient,
    private val supabaseUrl: String,
    private val supabasePublishableKey: String,
    private val tokenProvider: suspend () -> String,
    private val clock: Clock = Clock.System,
    maxRetries: Int = 3,
) : ApiClientBase(maxRetries), CloudSyncApi {

    private val restBase: String get() = "$supabaseUrl/rest/v1"

    // =========================================================================
    // WorkoutSession CRUD
    // =========================================================================

    /**
     * Returns all workout sessions for the authenticated user, newest first.
     */
    override suspend fun getWorkoutSessions(): List<WorkoutSession> = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/workout_sessions") {
            supabaseHeaders(token)
            url.parameters.append("order", "started_at.desc")
        }.also { it.expectSuccess() }
            .body<List<WorkoutSessionDTO>>()
            .map { it.toDomain() }
    }

    /**
     * Returns a single workout session by [id].
     *
     * @throws ApiException.NotFound if no session with [id] exists.
     */
    override suspend fun getWorkoutSession(id: String): WorkoutSession = withRetry {
        val token = tokenProvider()
        val list = httpClient.get("$restBase/workout_sessions") {
            supabaseHeaders(token)
            url.parameters.append("id", "eq.$id")
            url.parameters.append("limit", "1")
        }.also { it.expectSuccess() }
            .body<List<WorkoutSessionDTO>>()

        list.firstOrNull()?.toDomain()
            ?: throw ApiException.NotFound(
                message = "WorkoutSession not found: $id",
                resourceType = "WorkoutSession",
                resourceId = id,
            )
    }

    /**
     * Returns all workout sessions with [startedAt] in [[from], [to]] (inclusive).
     */
    suspend fun getWorkoutSessionsByDateRange(
        from: Instant,
        to: Instant,
    ): List<WorkoutSession> = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/workout_sessions") {
            supabaseHeaders(token)
            url.parameters.append("started_at", "gte.$from")
            url.parameters.append("started_at", "lte.$to")
            url.parameters.append("order", "started_at.desc")
        }.also { it.expectSuccess() }
            .body<List<WorkoutSessionDTO>>()
            .map { it.toDomain() }
    }

    /**
     * Creates a new workout session and returns the server-assigned row.
     */
    override suspend fun createWorkoutSession(request: CreateWorkoutSessionRequest): WorkoutSession =
        withRetry {
            val token = tokenProvider()
            httpClient.post("$restBase/workout_sessions") {
                supabaseHeaders(token)
                header("Prefer", "return=representation")
                contentType(ContentType.Application.Json)
                setBody(request)
            }.also { it.expectSuccess() }
                .body<List<WorkoutSessionDTO>>()
                .first()
                .toDomain()
        }

    /**
     * Partially updates a workout session and returns the updated row.
     *
     * Only non-null fields in [request] are sent to the server.
     *
     * @throws ApiException.NotFound if no session with [id] exists.
     */
    override suspend fun updateWorkoutSession(
        id: String,
        request: UpdateWorkoutSessionRequest,
    ): WorkoutSession = withRetry {
        val token = tokenProvider()
        val list = httpClient.patch("$restBase/workout_sessions") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            url.parameters.append("id", "eq.$id")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<WorkoutSessionDTO>>()

        list.firstOrNull()?.toDomain()
            ?: throw ApiException.NotFound(
                message = "WorkoutSession not found: $id",
                resourceType = "WorkoutSession",
                resourceId = id,
            )
    }

    /**
     * Deletes a workout session by [id].
     *
     * All associated [PushUpRecord] rows are cascade-deleted by the database.
     */
    suspend fun deleteWorkoutSession(id: String): Unit = withRetry {
        val token = tokenProvider()
        httpClient.delete("$restBase/workout_sessions") {
            supabaseHeaders(token)
            url.parameters.append("id", "eq.$id")
        }.expectSuccess()
    }

    // =========================================================================
    // PushUpRecord CRUD
    // =========================================================================

    /**
     * Returns all push-up records for [sessionId], ordered by timestamp ascending.
     */
    suspend fun getPushUpRecords(sessionId: String): List<PushUpRecord> = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/push_up_records") {
            supabaseHeaders(token)
            url.parameters.append("session_id", "eq.$sessionId")
            url.parameters.append("order", "timestamp.asc")
        }.also { it.expectSuccess() }
            .body<List<PushUpRecordDTO>>()
            .map { it.toDomain() }
    }

    /**
     * Inserts a single push-up record and returns the server-assigned row.
     */
    suspend fun createPushUpRecord(request: CreatePushUpRecordRequest): PushUpRecord = withRetry {
        val token = tokenProvider()
        httpClient.post("$restBase/push_up_records") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<PushUpRecordDTO>>()
            .first()
            .toDomain()
    }

    /**
     * Bulk-inserts push-up records in a single request and returns the created rows.
     *
     * Supabase PostgREST accepts a JSON array for bulk inserts.
     * Returns an empty list immediately when [requests] is empty.
     */
    suspend fun createPushUpRecords(
        requests: List<CreatePushUpRecordRequest>,
    ): List<PushUpRecord> = withRetry {
        if (requests.isEmpty()) return@withRetry emptyList()
        val token = tokenProvider()
        httpClient.post("$restBase/push_up_records") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            contentType(ContentType.Application.Json)
            setBody(requests)
        }.also { it.expectSuccess() }
            .body<List<PushUpRecordDTO>>()
            .map { it.toDomain() }
    }

    // =========================================================================
    // TimeCredit CRUD
    // =========================================================================

    /**
     * Returns the time credit record for [userId], or `null` if none exists yet.
     *
     * There is at most one row per user (UNIQUE constraint on `user_id`).
     */
    override suspend fun getTimeCredit(userId: String): TimeCredit? = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/time_credits") {
            supabaseHeaders(token)
            url.parameters.append("user_id", "eq.$userId")
            url.parameters.append("limit", "1")
        }.also { it.expectSuccess() }
            .body<List<TimeCreditDTO>>()
            .firstOrNull()
            ?.toTimeCreditDomain(clock)
    }

    /**
     * Partially updates the time credit record for [userId] and returns the updated row.
     *
     * @throws ApiException.NotFound if no time credit record exists for [userId].
     */
    override suspend fun updateTimeCredit(
        userId: String,
        request: UpdateTimeCreditRequest,
    ): TimeCredit = withRetry {
        val token = tokenProvider()
        val list = httpClient.patch("$restBase/time_credits") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            url.parameters.append("user_id", "eq.$userId")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<TimeCreditDTO>>()

        list.firstOrNull()?.toTimeCreditDomain(clock)
            ?: throw ApiException.NotFound(
                message = "TimeCredit not found for user: $userId",
                resourceType = "TimeCredit",
                resourceId = userId,
            )
    }

    // =========================================================================
    // User Profile CRUD
    // =========================================================================

    /**
     * Returns the user profile row for [userId] from public.users, or `null` if not found.
     */
    override suspend fun getUserProfile(userId: String): UserProfileDTO? = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/users") {
            supabaseHeaders(token)
            url.parameters.append("id", "eq.$userId")
            url.parameters.append("limit", "1")
        }.also { it.expectSuccess() }
            .body<List<UserProfileDTO>>()
            .firstOrNull()
    }

    /**
     * Updates the display name for [userId] in public.users.
     *
     * @throws ApiException.NotFound if no user row exists for [userId].
     */
    override suspend fun updateUserProfile(
        userId: String,
        request: UpdateUserProfileRequest,
    ): UserProfileDTO = withRetry {
        val token = tokenProvider()
        val list = httpClient.patch("$restBase/users") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            url.parameters.append("id", "eq.$userId")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<UserProfileDTO>>()

        list.firstOrNull()
            ?: throw ApiException.NotFound(
                message = "User profile not found: $userId",
                resourceType = "User",
                resourceId = userId,
            )
    }

    // =========================================================================
    // User settings — dashboard widget order (public.user_settings)
    // =========================================================================

    override suspend fun getUserSettingsDashboardWidgetOrderJson(userId: String): String? = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/user_settings") {
            supabaseHeaders(token)
            url.parameters.append("user_id", "eq.$userId")
            url.parameters.append("select", "dashboard_widget_order_json")
            url.parameters.append("limit", "1")
        }.also { it.expectSuccess() }
            .body<List<UserSettingsCloudRowDTO>>()
            .firstOrNull()
            ?.dashboardWidgetOrderJson
    }

    override suspend fun patchUserSettingsDashboardWidgetOrderJson(userId: String, json: String?) = withRetry {
        val token = tokenProvider()
        httpClient.patch("$restBase/user_settings") {
            supabaseHeaders(token)
            header("Prefer", "return=minimal")
            url.parameters.append("user_id", "eq.$userId")
            contentType(ContentType.Application.Json)
            setBody(mapOf("dashboard_widget_order_json" to json))
        }.also { it.expectSuccess() }
        Unit
    }

    // =========================================================================
    // UserLevel CRUD
    // =========================================================================

    /**
     * Returns the user_levels record for [userId], or `null` if none exists yet.
     */
    override suspend fun getUserLevel(userId: String): UserLevel? = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/user_levels") {
            supabaseHeaders(token)
            url.parameters.append("user_id", "eq.$userId")
            url.parameters.append("limit", "1")
        }.also { it.expectSuccess() }
            .body<List<UserLevelDTO>>()
            .firstOrNull()
            ?.toUserLevelDomain()
    }

    /**
     * Upserts the user_levels record for [userId].
     *
     * Uses Supabase's upsert endpoint (POST with `Prefer: resolution=merge-duplicates`)
     * so the row is created on first sync and updated on subsequent syncs.
     *
     * @throws ApiException.NotFound if the upsert returns an empty list (should not happen).
     */
    override suspend fun upsertUserLevel(
        userId: String,
        request: UpsertUserLevelRequest,
    ): UserLevel = withRetry {
        val token = tokenProvider()
        val list = httpClient.post("$restBase/user_levels") {
            supabaseHeaders(token)
            header("Prefer", "return=representation,resolution=merge-duplicates")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<UserLevelDTO>>()

        list.firstOrNull()?.toUserLevelDomain()
            ?: throw ApiException.NotFound(
                message = "UserLevel upsert returned empty for user: $userId",
                resourceType = "UserLevel",
                resourceId = userId,
            )
    }

    // =========================================================================
    // ExerciseLevel CRUD
    // =========================================================================

    override suspend fun getExerciseLevels(userId: String): List<ExerciseLevel> = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/exercise_levels") {
            supabaseHeaders(token)
            url.parameters.append("user_id", "eq.$userId")
        }.also { it.expectSuccess() }
            .body<List<ExerciseLevelDTO>>()
            .mapNotNull { it.toExerciseLevelDomain() }
    }

    override suspend fun upsertExerciseLevel(
        userId: String,
        request: UpsertExerciseLevelRequest,
    ): ExerciseLevel? = withRetry {
        val token = tokenProvider()
        httpClient.post("$restBase/exercise_levels") {
            supabaseHeaders(token)
            header("Prefer", "return=representation,resolution=merge-duplicates")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<ExerciseLevelDTO>>()
            .firstOrNull()
            ?.toExerciseLevelDomain()
    }

    // =========================================================================
    // Username (via Supabase PostgREST -- always available, no backend needed)
    // =========================================================================

    /**
     * Checks whether [username] is available by querying the `users` table
     * directly via Supabase PostgREST.
     *
     * Uses a case-insensitive filter (`ilike`) so "John" and "john" are treated
     * as the same username. Returns [UsernameCheckResponse.available] = true
     * when no row with that username exists, or when the only matching row
     * belongs to the caller (so a user can "re-confirm" their own username).
     *
     * This does NOT require the Ktor backend to be running.
     */
    override suspend fun checkUsernameAvailability(username: String): UsernameCheckResponse =
        withRetry {
            val token = tokenProvider()
            val rows = httpClient.get("$restBase/users") {
                supabaseHeaders(token)
                // ilike = case-insensitive LIKE; exact match via "eq." would miss
                // case variants that the DB constraint would reject anyway.
                url.parameters.append("username", "ilike.$username")
                url.parameters.append("select", "id")
            }.also { it.expectSuccess() }
                .body<List<Map<String, String>>>()

            // Available when: no row found, OR the only row is the caller's own.
            val callerId = runCatching { tokenProvider() }.getOrNull()
            val available = rows.isEmpty() ||
                rows.all { it["id"] == callerId }

            UsernameCheckResponse(username = username, available = available)
        }

    /**
     * Sets the username for the authenticated user via Supabase PostgREST PATCH.
     *
     * Uses `?id=eq.<userId>` to target only the caller's row (RLS also enforces
     * this). Returns the updated username on success.
     *
     * Note: uniqueness is enforced by the `idx_users_username_unique` partial
     * index in Supabase. A duplicate will result in a 409 / 23505 error from
     * PostgREST which is mapped to [ApiException.Conflict].
     */
    override suspend fun setUsername(request: SetUsernameRequest): String = withRetry {
        val token = tokenProvider()
        val username = request.username.trim().lowercase()

        // We need the caller's user ID to target the correct row.
        // Decode it from the JWT sub claim via the /auth/v1/user endpoint.
        val userProfile = httpClient.get("$supabaseUrl/auth/v1/user") {
            header("apikey", supabasePublishableKey)
            bearerAuth(token)
        }.also { it.expectSuccess() }
            .body<Map<String, kotlinx.serialization.json.JsonElement>>()

        val userId = userProfile["id"]?.toString()?.trim('"')
            ?: throw ApiException.Unknown(message = "Could not determine user ID from JWT")

        httpClient.patch("$restBase/users") {
            supabaseHeaders(token)
            url.parameters.append("id", "eq.$userId")
            header("Prefer", "return=minimal")
            contentType(ContentType.Application.Json)
            setBody(mapOf("username" to username))
        }.also { it.expectSuccess() }

        username
    }

    // =========================================================================
    // JoggingSession CRUD
    // =========================================================================

    override suspend fun getJoggingSessions(): List<JoggingSession> = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/jogging_sessions") {
            supabaseHeaders(token)
            url.parameters.append("order", "started_at.desc")
        }.also { it.expectSuccess() }
            .body<List<JoggingSessionDTO>>()
            .map { it.toDomain() }
    }

    override suspend fun getJoggingSession(id: String): JoggingSession = withRetry {
        val token = tokenProvider()
        val list = httpClient.get("$restBase/jogging_sessions") {
            supabaseHeaders(token)
            url.parameters.append("id", "eq.$id")
            url.parameters.append("limit", "1")
        }.also { it.expectSuccess() }
            .body<List<JoggingSessionDTO>>()

        list.firstOrNull()?.toDomain()
            ?: throw ApiException.NotFound(
                message = "JoggingSession not found: $id",
                resourceType = "JoggingSession",
                resourceId = id,
            )
    }

    override suspend fun createJoggingSession(request: CreateJoggingSessionRequest): JoggingSession =
        withRetry {
            val token = tokenProvider()
            httpClient.post("$restBase/jogging_sessions") {
                supabaseHeaders(token)
                header("Prefer", "return=representation")
                contentType(ContentType.Application.Json)
                setBody(request)
            }.also { it.expectSuccess() }
                .body<List<JoggingSessionDTO>>()
                .first()
                .toDomain()
        }

    override suspend fun updateJoggingSession(
        id: String,
        request: UpdateJoggingSessionRequest,
    ): JoggingSession = withRetry {
        val token = tokenProvider()
        val list = httpClient.patch("$restBase/jogging_sessions") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            url.parameters.append("id", "eq.$id")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<JoggingSessionDTO>>()

        list.firstOrNull()?.toDomain()
            ?: throw ApiException.NotFound(
                message = "JoggingSession not found: $id",
                resourceType = "JoggingSession",
                resourceId = id,
            )
    }

    // =========================================================================
    // RoutePoint CRUD
    // =========================================================================

    override suspend fun getRoutePoints(sessionId: String): List<RoutePoint> = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/route_points") {
            supabaseHeaders(token)
            url.parameters.append("session_id", "eq.$sessionId")
            url.parameters.append("order", "timestamp.asc")
        }.also { it.expectSuccess() }
            .body<List<RoutePointDTO>>()
            .map { it.toDomain() }
    }

    override suspend fun createRoutePoints(
        requests: List<CreateRoutePointRequest>,
    ): List<RoutePoint> = withRetry {
        if (requests.isEmpty()) return@withRetry emptyList()
        val token = tokenProvider()
        httpClient.post("$restBase/route_points") {
            supabaseHeaders(token)
            header("Prefer", "return=representation,resolution=ignore-duplicates")
            contentType(ContentType.Application.Json)
            setBody(requests)
        }.also { it.expectSuccess() }
            .body<List<RoutePointDTO>>()
            .map { it.toDomain() }
    }

    override suspend fun getJoggingSegments(sessionId: String): List<JoggingSegment> = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/jogging_segments") {
            supabaseHeaders(token)
            url.parameters.append("session_id", "eq.$sessionId")
            url.parameters.append("order", "started_at.asc")
        }.also { it.expectSuccess() }
            .body<List<JoggingSegmentDTO>>()
            .map { it.toDomain() }
    }

    override suspend fun replaceJoggingSegments(
        sessionId: String,
        requests: List<CreateJoggingSegmentRequest>,
    ) {
        val token = tokenProvider()
        // Delete existing segments first, then upsert new ones in a single
        // retry scope so a transient failure retries both steps.
        withRetry {
            httpClient.delete("$restBase/jogging_segments") {
                supabaseHeaders(token)
                url.parameters.append("session_id", "eq.$sessionId")
            }.also { it.expectSuccess() }

            if (requests.isNotEmpty()) {
                httpClient.post("$restBase/jogging_segments") {
                    supabaseHeaders(token)
                    header("Prefer", "return=minimal,resolution=ignore-duplicates")
                    contentType(ContentType.Application.Json)
                    setBody(requests)
                }.also { it.expectSuccess() }
            }
        }
    }

    override suspend fun getJoggingPlaybackEntries(sessionId: String): List<JoggingPlaybackEntry> = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/jogging_playback_entries") {
            supabaseHeaders(token)
            url.parameters.append("session_id", "eq.$sessionId")
            url.parameters.append("order", "started_at.asc")
        }.also { it.expectSuccess() }
            .body<List<JoggingPlaybackEntryDTO>>()
            .map { it.toDomain() }
    }

    override suspend fun replaceJoggingPlaybackEntries(
        sessionId: String,
        requests: List<CreateJoggingPlaybackEntryRequest>,
    ) {
        val token = tokenProvider()
        withRetry {
            httpClient.delete("$restBase/jogging_playback_entries") {
                supabaseHeaders(token)
                url.parameters.append("session_id", "eq.$sessionId")
            }.also { it.expectSuccess() }

            if (requests.isNotEmpty()) {
                httpClient.post("$restBase/jogging_playback_entries") {
                    supabaseHeaders(token)
                    header("Prefer", "return=minimal,resolution=ignore-duplicates")
                    contentType(ContentType.Application.Json)
                    setBody(requests)
                }.also { it.expectSuccess() }
            }
        }
    }

    // =========================================================================
    // Live Jogging Status (Presence)
    // =========================================================================

    override suspend fun upsertLiveJoggingStatus(
        request: UpsertLiveJoggingStatusRequest,
    ): Unit = withRetry {
        val token = tokenProvider()
        httpClient.post("$restBase/live_jogging_status") {
            supabaseHeaders(token)
            header("Prefer", "resolution=merge-duplicates")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
    }

    override suspend fun deleteLiveJoggingStatus(userId: String): Unit = withRetry {
        val token = tokenProvider()
        httpClient.delete("$restBase/live_jogging_status") {
            supabaseHeaders(token)
            url.parameters.append("user_id", "eq.$userId")
        }.also { it.expectSuccess() }
    }

    override suspend fun getLiveJoggingStatuses(
        userIds: List<String>,
    ): List<LiveJoggingStatusDTO> = withRetry {
        if (userIds.isEmpty()) return@withRetry emptyList()
        val token = tokenProvider()
        val inFilter = userIds.joinToString(",") { "\"$it\"" }
        httpClient.get("$restBase/live_jogging_status") {
            supabaseHeaders(token)
            url.parameters.append("user_id", "in.($inFilter)")
        }.also { it.expectSuccess() }
            .body<List<LiveJoggingStatusDTO>>()
    }

    // =========================================================================
    // Social Running
    // =========================================================================

    override suspend fun getRunEvents(): List<RunEventDTO> = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/run_events") {
            supabaseHeaders(token)
            url.parameters.append("order", "planned_start_at.asc")
        }.also { it.expectSuccess() }
            .body<List<RunEventDTO>>()
    }

    override suspend fun getRunEvent(id: String): RunEventDTO? = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/run_events") {
            supabaseHeaders(token)
            url.parameters.append("id", "eq.$id")
            url.parameters.append("limit", "1")
        }.also { it.expectSuccess() }
            .body<List<RunEventDTO>>()
            .firstOrNull()
    }

    override suspend fun createRunEvent(request: CreateRunEventRequest): RunEventDTO? = withRetry {
        val token = tokenProvider()
        httpClient.post("$restBase/run_events") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<RunEventDTO>>()
            .firstOrNull()
    }

    override suspend fun updateRunEvent(id: String, request: UpdateRunEventRequest): RunEventDTO? = withRetry {
        val token = tokenProvider()
        httpClient.patch("$restBase/run_events") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            url.parameters.append("id", "eq.$id")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<RunEventDTO>>()
            .firstOrNull()
    }

    override suspend fun getRunEventParticipants(eventId: String): List<RunEventParticipantDTO> = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/run_event_participants") {
            supabaseHeaders(token)
            url.parameters.append("event_id", "eq.$eventId")
            url.parameters.append("order", "created_at.asc")
        }.also { it.expectSuccess() }
            .body<List<RunEventParticipantDTO>>()
    }

    override suspend fun createRunEventParticipants(
        requests: List<CreateRunEventParticipantRequest>,
    ): List<RunEventParticipantDTO> = withRetry {
        if (requests.isEmpty()) return@withRetry emptyList()
        val token = tokenProvider()
        httpClient.post("$restBase/run_event_participants") {
            supabaseHeaders(token)
            header("Prefer", "return=representation,resolution=merge-duplicates")
            contentType(ContentType.Application.Json)
            setBody(requests)
        }.also { it.expectSuccess() }
            .body<List<RunEventParticipantDTO>>()
    }

    override suspend fun updateRunEventParticipant(
        eventId: String,
        userId: String,
        request: UpdateRunEventParticipantRequest,
    ): RunEventParticipantDTO? = withRetry {
        val token = tokenProvider()
        httpClient.patch("$restBase/run_event_participants") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            url.parameters.append("event_id", "eq.$eventId")
            url.parameters.append("user_id", "eq.$userId")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<RunEventParticipantDTO>>()
            .firstOrNull()
    }

    override suspend fun getLiveRunSessions(): List<LiveRunSessionDTO> = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/live_run_sessions") {
            supabaseHeaders(token)
            url.parameters.append("order", "last_activity_at.desc")
        }.also { it.expectSuccess() }
            .body<List<LiveRunSessionDTO>>()
    }

    override suspend fun getLiveRunSession(id: String): LiveRunSessionDTO? = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/live_run_sessions") {
            supabaseHeaders(token)
            url.parameters.append("id", "eq.$id")
            url.parameters.append("limit", "1")
        }.also { it.expectSuccess() }
            .body<List<LiveRunSessionDTO>>()
            .firstOrNull()
    }

    override suspend fun createLiveRunSession(request: CreateLiveRunSessionRequest): LiveRunSessionDTO? = withRetry {
        val token = tokenProvider()
        httpClient.post("$restBase/live_run_sessions") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<LiveRunSessionDTO>>()
            .firstOrNull()
    }

    override suspend fun updateLiveRunSession(
        id: String,
        request: UpdateLiveRunSessionRequest,
    ): LiveRunSessionDTO? = withRetry {
        val token = tokenProvider()
        httpClient.patch("$restBase/live_run_sessions") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            url.parameters.append("id", "eq.$id")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<LiveRunSessionDTO>>()
            .firstOrNull()
    }

    override suspend fun getLiveRunParticipants(sessionId: String): List<LiveRunParticipantDTO> = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/live_run_participants") {
            supabaseHeaders(token)
            url.parameters.append("session_id", "eq.$sessionId")
            url.parameters.append("order", "joined_at.asc")
        }.also { it.expectSuccess() }
            .body<List<LiveRunParticipantDTO>>()
    }

    override suspend fun createLiveRunParticipants(
        requests: List<CreateLiveRunParticipantRequest>,
    ): List<LiveRunParticipantDTO> = withRetry {
        if (requests.isEmpty()) return@withRetry emptyList()
        val token = tokenProvider()
        httpClient.post("$restBase/live_run_participants") {
            supabaseHeaders(token)
            header("Prefer", "return=representation,resolution=merge-duplicates")
            contentType(ContentType.Application.Json)
            setBody(requests)
        }.also { it.expectSuccess() }
            .body<List<LiveRunParticipantDTO>>()
    }

    override suspend fun updateLiveRunParticipant(
        sessionId: String,
        userId: String,
        request: UpdateLiveRunParticipantRequest,
    ): LiveRunParticipantDTO? = withRetry {
        val token = tokenProvider()
        httpClient.patch("$restBase/live_run_participants") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            url.parameters.append("session_id", "eq.$sessionId")
            url.parameters.append("user_id", "eq.$userId")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<LiveRunParticipantDTO>>()
            .firstOrNull()
    }

    override suspend fun getLiveRunPresence(sessionId: String): List<LiveRunPresenceDTO> = withRetry {
        val token = tokenProvider()
        httpClient.get("$restBase/live_run_presence") {
            supabaseHeaders(token)
            url.parameters.append("session_id", "eq.$sessionId")
            url.parameters.append("order", "last_seen_at.desc")
        }.also { it.expectSuccess() }
            .body<List<LiveRunPresenceDTO>>()
    }

    override suspend fun upsertLiveRunPresence(request: UpsertLiveRunPresenceRequest): LiveRunPresenceDTO? = withRetry {
        val token = tokenProvider()
        httpClient.post("$restBase/live_run_presence") {
            supabaseHeaders(token)
            header("Prefer", "return=representation,resolution=merge-duplicates")
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<List<LiveRunPresenceDTO>>()
            .firstOrNull()
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    /**
     * Adds the two headers required by every Supabase PostgREST request:
     * - `apikey`: identifies the Supabase project (public, not secret)
     * - `Authorization: Bearer <token>`: proves the user's identity for RLS
     */
    private fun HttpRequestBuilder.supabaseHeaders(token: String) {
        header("apikey", supabasePublishableKey)
        bearerAuth(token)
    }
}

// =============================================================================
// TimeCreditDTO -> domain mapper (file-private, not part of the public dto API)
// =============================================================================

/**
 * Maps a [TimeCreditDTO] to a [TimeCredit] domain model.
 *
 * Named `toTimeCreditDomain` rather than `toDomain` to avoid ambiguity with
 * the extension functions imported from the `dto` package.
 *
 * Falls back to [clock].now() when `updated_at` is absent or unparseable,
 * which can happen if the server omits the field in a partial response.
 *
 * For the daily fields, falls back to the all-time balance when the remote
 * record does not yet have daily fields (backward compatibility with older
 * server versions).
 */
private fun TimeCreditDTO.toTimeCreditDomain(clock: Clock): TimeCredit {
    val allTimeAvailable = (totalEarnedSeconds - totalSpentSeconds).coerceAtLeast(0L)
    return TimeCredit(
        userId = userId,
        totalEarnedSeconds = totalEarnedSeconds,
        totalSpentSeconds = totalSpentSeconds,
        dailyEarnedSeconds = dailyEarnedSeconds ?: allTimeAvailable,
        dailySpentSeconds = dailySpentSeconds ?: 0L,
        lastResetAt = lastResetAt
            ?.let { runCatching { Instant.parse(it) }.getOrNull() },
        lastUpdatedAt = updatedAt
            ?.let { runCatching { Instant.parse(it) }.getOrNull() }
            ?: clock.now(),
        syncStatus = SyncStatus.SYNCED,
    )
}

/**
 * Maps a [UserLevelDTO] to a [UserLevel] domain model.
 *
 * The level and progress fields are derived from [totalXp] via
 * [LevelCalculator.fromTotalXp] — they are not stored in the remote DB.
 */
private fun UserLevelDTO.toUserLevelDomain(): UserLevel =
    LevelCalculator.fromTotalXp(userId = userId, totalXp = totalXp)

/**
 * Maps an [ExerciseLevelDTO] to an [ExerciseLevel] domain model.
 *
 * Returns `null` if the [exerciseType] is not a known [ExerciseType].
 */
private fun ExerciseLevelDTO.toExerciseLevelDomain(): ExerciseLevel? {
    val type = runCatching { ExerciseType.fromId(exerciseType) }.getOrNull() ?: return null
    return LevelCalculator.exerciseLevelFromTotalXp(
        userId = userId,
        exerciseType = type,
        totalXp = totalXp,
    )
}
