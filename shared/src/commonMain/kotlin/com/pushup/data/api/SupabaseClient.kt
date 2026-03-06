package com.pushup.data.api

import com.pushup.data.api.dto.CreatePushUpRecordRequest
import com.pushup.data.api.dto.CreateWorkoutSessionRequest
import com.pushup.data.api.dto.PushUpRecordDTO
import com.pushup.data.api.dto.TimeCreditDTO
import com.pushup.data.api.dto.UpdateTimeCreditRequest
import com.pushup.data.api.dto.UpdateWorkoutSessionRequest
import com.pushup.data.api.dto.WorkoutSessionDTO
import com.pushup.data.api.dto.toDomain
import com.pushup.domain.model.PushUpRecord
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
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
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.http.isSuccess
import kotlinx.coroutines.delay
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.serialization.SerializationException

/**
 * Wrapper around the Supabase PostgREST REST API for CRUD operations on
 * [WorkoutSession], [PushUpRecord], and [TimeCredit].
 *
 * ## Authentication
 * Every request includes the user's JWT token in the `Authorization: Bearer <token>`
 * header. The token is retrieved lazily via [tokenProvider] so that it is always
 * fresh (Supabase tokens expire after 1 hour by default).
 *
 * ## Error handling
 * All HTTP and network errors are mapped to [ApiException] subclasses before
 * they propagate to callers. Transient errors ([ApiException.Timeout],
 * [ApiException.NetworkError], [ApiException.ServiceUnavailable]) are retried
 * automatically up to [maxRetries] times with exponential back-off.
 *
 * ## Supabase REST conventions
 * - Base URL: `https://<project-ref>.supabase.co/rest/v1`
 * - `apikey` header: the Supabase anon key (required for all requests)
 * - `Authorization` header: `Bearer <jwt>` (required for RLS-protected tables)
 * - `Prefer: return=representation` header: makes POST/PATCH return the created/updated row
 * - `Content-Type: application/json`
 *
 * @property httpClient      Configured [HttpClient] with JSON content negotiation.
 * @property supabaseUrl     Base URL of the Supabase project, e.g. `https://<ref>.supabase.co`.
 * @property supabaseAnonKey The Supabase anon (public) API key.
 * @property tokenProvider   Suspending function that returns the current JWT access token.
 * @property clock           [Clock] used for timestamp fallbacks.
 * @property maxRetries      Maximum number of retry attempts for transient errors (default 3).
 */
class SupabaseClient(
    private val httpClient: HttpClient,
    private val supabaseUrl: String,
    private val supabaseAnonKey: String,
    private val tokenProvider: suspend () -> String,
    private val clock: Clock = Clock.System,
    private val maxRetries: Int = 3,
) {

    // Base URL for the PostgREST REST API
    private val restBase: String get() = "$supabaseUrl/rest/v1"

    // =========================================================================
    // WorkoutSession CRUD
    // =========================================================================

    /**
     * Fetches all workout sessions for the authenticated user, ordered by
     * [WorkoutSession.startedAt] descending (newest first).
     */
    suspend fun getWorkoutSessions(): List<WorkoutSession> = withRetry {
        val token = tokenProvider()
        val response = httpClient.get("$restBase/workout_sessions") {
            supabaseHeaders(token)
            url.parameters.append("order", "started_at.desc")
        }
        response.expectSuccess()
        response.body<List<WorkoutSessionDTO>>().map { it.toDomain() }
    }

    /**
     * Fetches a single workout session by its [id].
     *
     * @throws ApiException.NotFound if no session with the given [id] exists.
     */
    suspend fun getWorkoutSession(id: String): WorkoutSession = withRetry {
        val token = tokenProvider()
        val response = httpClient.get("$restBase/workout_sessions") {
            supabaseHeaders(token)
            url.parameters.append("id", "eq.$id")
            url.parameters.append("limit", "1")
        }
        response.expectSuccess()
        response.body<List<WorkoutSessionDTO>>().firstOrNull()?.toDomain()
            ?: throw ApiException.NotFound(
                message = "WorkoutSession not found: $id",
                resourceType = "WorkoutSession",
                resourceId = id,
            )
    }

    /**
     * Fetches workout sessions within a date range.
     */
    suspend fun getWorkoutSessionsByDateRange(from: Instant, to: Instant): List<WorkoutSession> =
        withRetry {
            val token = tokenProvider()
            val response = httpClient.get("$restBase/workout_sessions") {
                supabaseHeaders(token)
                url.parameters.append("started_at", "gte.$from")
                url.parameters.append("started_at", "lte.$to")
                url.parameters.append("order", "started_at.desc")
            }
            response.expectSuccess()
            response.body<List<WorkoutSessionDTO>>().map { it.toDomain() }
        }

    /**
     * Creates a new workout session in Supabase.
     *
     * @return The created [WorkoutSession] as returned by the server.
     */
    suspend fun createWorkoutSession(request: CreateWorkoutSessionRequest): WorkoutSession =
        withRetry {
            val token = tokenProvider()
            val response = httpClient.post("$restBase/workout_sessions") {
                supabaseHeaders(token)
                header("Prefer", "return=representation")
                contentType(ContentType.Application.Json)
                setBody(request)
            }
            response.expectSuccess()
            response.body<List<WorkoutSessionDTO>>().first().toDomain()
        }

    /**
     * Updates an existing workout session identified by [id].
     *
     * @throws ApiException.NotFound if no session with the given [id] exists.
     */
    suspend fun updateWorkoutSession(
        id: String,
        request: UpdateWorkoutSessionRequest,
    ): WorkoutSession = withRetry {
        val token = tokenProvider()
        val response = httpClient.patch("$restBase/workout_sessions") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            url.parameters.append("id", "eq.$id")
            contentType(ContentType.Application.Json)
            setBody(request)
        }
        response.expectSuccess()
        response.body<List<WorkoutSessionDTO>>().firstOrNull()?.toDomain()
            ?: throw ApiException.NotFound(
                message = "WorkoutSession not found: $id",
                resourceType = "WorkoutSession",
                resourceId = id,
            )
    }

    /**
     * Deletes a workout session by its [id].
     *
     * Supabase cascades the delete to all associated [PushUpRecord] rows
     * via the `ON DELETE CASCADE` foreign key constraint.
     */
    suspend fun deleteWorkoutSession(id: String) {
        withRetry<Unit> {
            val token = tokenProvider()
            val response = httpClient.delete("$restBase/workout_sessions") {
                supabaseHeaders(token)
                url.parameters.append("id", "eq.$id")
            }
            response.expectSuccess()
        }
    }

    // =========================================================================
    // PushUpRecord CRUD
    // =========================================================================

    /**
     * Fetches all push-up records for a given [sessionId].
     */
    suspend fun getPushUpRecords(sessionId: String): List<PushUpRecord> = withRetry {
        val token = tokenProvider()
        val response = httpClient.get("$restBase/push_up_records") {
            supabaseHeaders(token)
            url.parameters.append("session_id", "eq.$sessionId")
            url.parameters.append("order", "timestamp.asc")
        }
        response.expectSuccess()
        response.body<List<PushUpRecordDTO>>().map { it.toDomain() }
    }

    /**
     * Inserts a single push-up record.
     *
     * @return The created [PushUpRecord] as returned by the server.
     */
    suspend fun createPushUpRecord(request: CreatePushUpRecordRequest): PushUpRecord = withRetry {
        val token = tokenProvider()
        val response = httpClient.post("$restBase/push_up_records") {
            supabaseHeaders(token)
            header("Prefer", "return=representation")
            contentType(ContentType.Application.Json)
            setBody(request)
        }
        response.expectSuccess()
        response.body<List<PushUpRecordDTO>>().first().toDomain()
    }

    /**
     * Inserts multiple push-up records in a single request.
     *
     * Supabase PostgREST supports bulk inserts by sending a JSON array.
     *
     * @return List of created [PushUpRecord] domain models.
     */
    suspend fun createPushUpRecords(requests: List<CreatePushUpRecordRequest>): List<PushUpRecord> =
        withRetry {
            if (requests.isEmpty()) return@withRetry emptyList()
            val token = tokenProvider()
            val response = httpClient.post("$restBase/push_up_records") {
                supabaseHeaders(token)
                header("Prefer", "return=representation")
                contentType(ContentType.Application.Json)
                setBody(requests)
            }
            response.expectSuccess()
            response.body<List<PushUpRecordDTO>>().map { it.toDomain() }
        }

    // =========================================================================
    // TimeCredit CRUD
    // =========================================================================

    /**
     * Fetches the time credit record for the authenticated user.
     *
     * There is exactly one row per user in the `time_credits` table.
     *
     * @return The [TimeCredit] domain model, or `null` if no record exists yet.
     */
    suspend fun getTimeCredit(userId: String): TimeCredit? = withRetry {
        val token = tokenProvider()
        val response = httpClient.get("$restBase/time_credits") {
            supabaseHeaders(token)
            url.parameters.append("user_id", "eq.$userId")
            url.parameters.append("limit", "1")
        }
        response.expectSuccess()
        response.body<List<TimeCreditDTO>>().firstOrNull()?.toTimeCreditDomain(clock)
    }

    /**
     * Updates the time credit record for the authenticated user.
     *
     * @throws ApiException.NotFound if no time credit record exists for [userId].
     */
    suspend fun updateTimeCredit(userId: String, request: UpdateTimeCreditRequest): TimeCredit =
        withRetry {
            val token = tokenProvider()
            val response = httpClient.patch("$restBase/time_credits") {
                supabaseHeaders(token)
                header("Prefer", "return=representation")
                url.parameters.append("user_id", "eq.$userId")
                contentType(ContentType.Application.Json)
                setBody(request)
            }
            response.expectSuccess()
            response.body<List<TimeCreditDTO>>().firstOrNull()?.toTimeCreditDomain(clock)
                ?: throw ApiException.NotFound(
                    message = "TimeCredit not found for user: $userId",
                    resourceType = "TimeCredit",
                    resourceId = userId,
                )
        }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /**
     * Adds the standard Supabase headers to every request:
     * - `apikey`: the Supabase anon key (required for all requests)
     * - `Authorization`: `Bearer <jwt>` (required for RLS-protected tables)
     */
    private fun HttpRequestBuilder.supabaseHeaders(token: String) {
        header("apikey", supabaseAnonKey)
        header("Authorization", "Bearer $token")
    }

    /**
     * Throws an [ApiException] if the HTTP response status is not a success (2xx).
     */
    private suspend fun HttpResponse.expectSuccess() {
        if (status.isSuccess()) return
        val body = runCatching { bodyAsText() }.getOrNull()
        throw when (status) {
            HttpStatusCode.Unauthorized        -> ApiException.Unauthorized(body ?: "Unauthorized")
            HttpStatusCode.Forbidden           -> ApiException.Forbidden(body ?: "Forbidden")
            HttpStatusCode.NotFound            -> ApiException.NotFound(body ?: "Not found")
            HttpStatusCode.BadRequest          -> ApiException.BadRequest(serverMessage = body)
            HttpStatusCode.UnprocessableEntity -> ApiException.BadRequest(serverMessage = body)
            HttpStatusCode.Conflict            -> ApiException.Conflict(body ?: "Conflict")
            HttpStatusCode.ServiceUnavailable  -> ApiException.ServiceUnavailable(body ?: "Service unavailable")
            else                               -> ApiException.ServerError(
                statusCode = status.value,
                serverMessage = body,
            )
        }
    }

    /**
     * Executes [block] with automatic retry logic for transient errors.
     *
     * Retries up to [maxRetries] times on [ApiException.isTransient] errors,
     * using exponential back-off (100ms * 2^attempt). Non-transient errors
     * and [SerializationException]s are rethrown immediately without retrying.
     */
    private suspend fun <T> withRetry(block: suspend () -> T): T {
        var lastException: ApiException? = null
        repeat(maxRetries) { attempt ->
            try {
                return block()
            } catch (e: SerializationException) {
                throw ApiException.ParseError(cause = e)
            } catch (e: ApiException) {
                if (!e.isTransient) throw e
                lastException = e
                val delayMs = 100L * (1L shl attempt)
                delay(delayMs)
            } catch (e: Exception) {
                lastException = ApiException.NetworkError(
                    message = e.message ?: "Network error",
                    cause = e,
                )
                val delayMs = 100L * (1L shl attempt)
                delay(delayMs)
            }
        }
        throw lastException ?: ApiException.Unknown("All retry attempts exhausted")
    }
}

// =============================================================================
// TimeCreditDTO -> domain mapper
// =============================================================================

/**
 * Converts a [TimeCreditDTO] from the Supabase REST API into a [TimeCredit] domain model.
 *
 * Named `toTimeCreditDomain` (not `toDomain`) to avoid ambiguity with the
 * extension functions imported from the dto package.
 */
private fun TimeCreditDTO.toTimeCreditDomain(clock: Clock): TimeCredit {
    val now = clock.now()
    return TimeCredit(
        userId = userId,
        totalEarnedSeconds = totalEarnedSeconds,
        totalSpentSeconds = totalSpentSeconds,
        lastUpdatedAt = updatedAt?.let {
            runCatching { Instant.parse(it) }.getOrDefault(now)
        } ?: now,
        syncStatus = SyncStatus.SYNCED,
    )
}
