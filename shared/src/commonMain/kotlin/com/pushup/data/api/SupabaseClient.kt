package com.pushup.data.api

import com.pushup.data.api.dto.CreatePushUpRecordRequest
import com.pushup.data.api.dto.CreateWorkoutSessionRequest
import com.pushup.data.api.dto.PushUpRecordDTO
import com.pushup.data.api.dto.TimeCreditDTO
import com.pushup.data.api.dto.UpdateTimeCreditRequest
import com.pushup.data.api.dto.UpdateUserProfileRequest
import com.pushup.data.api.dto.UpdateWorkoutSessionRequest
import com.pushup.data.api.dto.UpsertUserLevelRequest
import com.pushup.data.api.dto.UserLevelDTO
import com.pushup.data.api.dto.UserProfileDTO
import com.pushup.data.api.dto.WorkoutSessionDTO
import com.pushup.data.api.dto.toDomain
import com.pushup.domain.model.LevelCalculator
import com.pushup.domain.model.PushUpRecord
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
 */
private fun TimeCreditDTO.toTimeCreditDomain(clock: Clock): TimeCredit = TimeCredit(
    userId = userId,
    totalEarnedSeconds = totalEarnedSeconds,
    totalSpentSeconds = totalSpentSeconds,
    lastUpdatedAt = updatedAt
        ?.let { runCatching { Instant.parse(it) }.getOrNull() }
        ?: clock.now(),
    syncStatus = SyncStatus.SYNCED,
)

/**
 * Maps a [UserLevelDTO] to a [UserLevel] domain model.
 *
 * The level and progress fields are derived from [totalXp] via
 * [LevelCalculator.fromTotalXp] — they are not stored in the remote DB.
 */
private fun UserLevelDTO.toUserLevelDomain(): UserLevel =
    LevelCalculator.fromTotalXp(userId = userId, totalXp = totalXp)
