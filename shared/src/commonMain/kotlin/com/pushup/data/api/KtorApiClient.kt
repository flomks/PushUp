package com.pushup.data.api

import com.pushup.data.api.dto.DailyStatsDTO
import com.pushup.data.api.dto.MonthlyStatsDTO
import com.pushup.data.api.dto.StreakDTO
import com.pushup.data.api.dto.TotalStatsDTO
import com.pushup.data.api.dto.WeeklyStatsDTO
import com.pushup.data.api.dto.toDomain
import com.pushup.domain.model.DailyStats
import com.pushup.domain.model.MonthlyStats
import com.pushup.domain.model.TotalStats
import com.pushup.domain.model.WeeklyStats
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.http.isSuccess
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.datetime.LocalDate
import kotlinx.serialization.SerializationException

/**
 * Client for the custom Ktor backend endpoints.
 *
 * The Ktor backend (`backend/`) exposes aggregated statistics endpoints that
 * are not available directly via the Supabase REST API. This client handles
 * all communication with those custom endpoints.
 *
 * ## Endpoints covered
 * | Method | Path                    | Description                          |
 * |--------|-------------------------|--------------------------------------|
 * | GET    | /api/stats/daily        | Daily statistics for a given date    |
 * | GET    | /api/stats/weekly       | Weekly statistics for a given week   |
 * | GET    | /api/stats/monthly      | Monthly statistics for a given month |
 * | GET    | /api/stats/total        | All-time statistics                  |
 * | GET    | /api/stats/streak       | Current and longest workout streak   |
 *
 * ## Authentication
 * Every request includes the user's JWT token in the `Authorization: Bearer <token>`
 * header. The token is retrieved lazily via [tokenProvider] so that it is always
 * fresh.
 *
 * ## Error handling
 * All HTTP and network errors are mapped to [ApiException] subclasses. Transient
 * errors are retried automatically up to [maxRetries] times with exponential back-off.
 *
 * @property httpClient     Configured [HttpClient] with JSON content negotiation.
 * @property backendBaseUrl Base URL of the Ktor backend, e.g. `https://api.pushup.com`.
 * @property tokenProvider  Suspending function that returns the current JWT access token.
 * @property maxRetries     Maximum number of retry attempts for transient errors (default 3).
 */
class KtorApiClient(
    private val httpClient: HttpClient,
    private val backendBaseUrl: String,
    private val tokenProvider: suspend () -> String,
    private val maxRetries: Int = 3,
) {

    // =========================================================================
    // Stats endpoints
    // =========================================================================

    /**
     * Fetches aggregated statistics for a single calendar day.
     *
     * Calls `GET /api/stats/daily?date=<YYYY-MM-DD>`.
     *
     * @param date The calendar date to fetch statistics for.
     * @return [DailyStats] domain model for the given date.
     * @throws ApiException on any network or HTTP error.
     */
    suspend fun getDailyStats(date: LocalDate): DailyStats = withRetry {
        val token = tokenProvider()
        val response = httpClient.get("$backendBaseUrl/api/stats/daily") {
            authHeader(token)
            url.parameters.append("date", date.toString())
        }
        response.expectSuccess()
        response.body<DailyStatsDTO>().toDomain()
    }

    /**
     * Fetches aggregated statistics for a calendar week.
     *
     * Calls `GET /api/stats/weekly?week_start=<YYYY-MM-DD>`.
     *
     * @param weekStart The Monday that starts the week (ISO-8601 date).
     * @return [WeeklyStats] domain model for the given week.
     * @throws ApiException on any network or HTTP error.
     */
    suspend fun getWeeklyStats(weekStart: LocalDate): WeeklyStats = withRetry {
        val token = tokenProvider()
        val response = httpClient.get("$backendBaseUrl/api/stats/weekly") {
            authHeader(token)
            url.parameters.append("week_start", weekStart.toString())
        }
        response.expectSuccess()
        response.body<WeeklyStatsDTO>().toDomain()
    }

    /**
     * Fetches aggregated statistics for a calendar month.
     *
     * Calls `GET /api/stats/monthly?month=<1-12>&year=<YYYY>`.
     *
     * @param month Month number (1-12).
     * @param year  Four-digit year.
     * @return [MonthlyStats] domain model for the given month.
     * @throws ApiException on any network or HTTP error.
     */
    suspend fun getMonthlyStats(month: Int, year: Int): MonthlyStats = withRetry {
        val token = tokenProvider()
        val response = httpClient.get("$backendBaseUrl/api/stats/monthly") {
            authHeader(token)
            url.parameters.append("month", month.toString())
            url.parameters.append("year", year.toString())
        }
        response.expectSuccess()
        response.body<MonthlyStatsDTO>().toDomain()
    }

    /**
     * Fetches all-time statistics for the authenticated user.
     *
     * Calls `GET /api/stats/total` and `GET /api/stats/streak` in parallel,
     * then merges the results into a single [TotalStats] domain model.
     *
     * @param userId The authenticated user's ID (used to populate [TotalStats.userId]).
     * @return [TotalStats] domain model with streak information included.
     * @throws ApiException on any network or HTTP error.
     */
    suspend fun getTotalStats(userId: String): TotalStats = coroutineScope {
        val totalDeferred = async { fetchTotalStats() }
        val streakDeferred = async { fetchStreak() }
        val totalDto = totalDeferred.await()
        val streakDto = streakDeferred.await()
        totalDto.toDomain(
            userId = userId,
            currentStreakDays = streakDto.currentStreak,
            longestStreakDays = streakDto.longestStreak,
        )
    }

    /**
     * Fetches the current and longest workout streak for the authenticated user.
     *
     * Calls `GET /api/stats/streak`.
     *
     * @return [StreakDTO] with streak information.
     * @throws ApiException on any network or HTTP error.
     */
    suspend fun getStreak(): StreakDTO = withRetry {
        fetchStreak()
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private suspend fun fetchTotalStats(): TotalStatsDTO = withRetry {
        val token = tokenProvider()
        val response = httpClient.get("$backendBaseUrl/api/stats/total") {
            authHeader(token)
        }
        response.expectSuccess()
        response.body<TotalStatsDTO>()
    }

    private suspend fun fetchStreak(): StreakDTO = withRetry {
        val token = tokenProvider()
        val response = httpClient.get("$backendBaseUrl/api/stats/streak") {
            authHeader(token)
        }
        response.expectSuccess()
        response.body<StreakDTO>()
    }

    /**
     * Adds the `Authorization: Bearer <token>` header to the request.
     */
    private fun io.ktor.client.request.HttpRequestBuilder.authHeader(token: String) {
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
