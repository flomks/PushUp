package com.pushup.data.api

import com.pushup.data.api.dto.DailyStatsDTO
import com.pushup.data.api.dto.MonthlyStatsDTO
import com.pushup.data.api.dto.SetUsernameRequest
import com.pushup.data.api.dto.StreakDTO
import com.pushup.data.api.dto.TotalStatsDTO
import com.pushup.data.api.dto.UsernameCheckResponse
import com.pushup.data.api.dto.WeeklyStatsDTO
import com.pushup.data.api.dto.toDomain
import com.pushup.domain.model.DailyStats
import com.pushup.domain.model.MonthlyStats
import com.pushup.domain.model.TotalStats
import com.pushup.domain.model.WeeklyStats
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.patch
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.datetime.LocalDate

/**
 * Client for the custom Ktor backend statistics endpoints.
 *
 * The Ktor backend (`backend/`) aggregates data from the Supabase database and
 * exposes it via REST endpoints that are not available through the Supabase
 * PostgREST API directly. This client handles all communication with those
 * custom endpoints.
 *
 * ## Endpoints
 * | Method | Path                    | Description                          |
 * |--------|-------------------------|--------------------------------------|
 * | GET    | /api/stats/daily        | Daily statistics for a given date    |
 * | GET    | /api/stats/weekly       | Weekly statistics for a given week   |
 * | GET    | /api/stats/monthly      | Monthly statistics for a given month |
 * | GET    | /api/stats/total        | All-time statistics                  |
 * | GET    | /api/stats/streak       | Current and longest workout streak   |
 *
 * ## Authentication
 * Every request includes `Authorization: Bearer <jwt>`. The token is fetched
 * lazily via [tokenProvider] on every call so it is always fresh.
 *
 * When a 401 is received, [onRefreshToken] is called (if provided) to force a
 * token refresh, and the request is retried once.
 *
 * ## Error handling
 * All HTTP and network errors are mapped to [ApiException] subclasses.
 * Transient errors are retried automatically (see [ApiClientBase.withRetry]).
 *
 * @property httpClient      Configured [HttpClient] (from [createHttpClient]).
 * @property backendBaseUrl  Ktor backend base URL, e.g. `https://api.pushup.com`.
 * @property tokenProvider   Returns the current JWT access token.
 * @property onRefreshToken  Optional callback to force a token refresh on 401.
 * @property maxRetries      Max retry attempts for transient errors (default 3).
 */
class KtorApiClient(
    private val httpClient: HttpClient,
    private val backendBaseUrl: String,
    private val tokenProvider: suspend () -> String,
    private val onRefreshToken: (suspend () -> Unit)? = null,
    maxRetries: Int = 3,
) : ApiClientBase(maxRetries) {

    /**
     * Executes [block] with retry logic. Uses [withRetryAndTokenRefresh] when
     * [onRefreshToken] is configured, otherwise falls back to [withRetry].
     */
    private suspend fun <T> retrying(block: suspend () -> T): T =
        if (onRefreshToken != null) {
            withRetryAndTokenRefresh(onRefreshToken, block)
        } else {
            withRetry(block)
        }

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Returns aggregated statistics for a single calendar [date].
     *
     * Calls `GET /api/stats/daily?date=<YYYY-MM-DD>`.
     */
    suspend fun getDailyStats(date: LocalDate): DailyStats = retrying {
        val token = tokenProvider()
        httpClient.get("$backendBaseUrl/api/stats/daily") {
            bearerAuth(token)
            url.parameters.append("date", date.toString())
        }.also { it.expectSuccess() }
            .body<DailyStatsDTO>()
            .toDomain()
    }

    /**
     * Returns aggregated statistics for the calendar week starting on [weekStart].
     *
     * Calls `GET /api/stats/weekly?week_start=<YYYY-MM-DD>`.
     *
     * @param weekStart The Monday that starts the ISO week.
     */
    suspend fun getWeeklyStats(weekStart: LocalDate): WeeklyStats = retrying {
        val token = tokenProvider()
        httpClient.get("$backendBaseUrl/api/stats/weekly") {
            bearerAuth(token)
            url.parameters.append("week_start", weekStart.toString())
        }.also { it.expectSuccess() }
            .body<WeeklyStatsDTO>()
            .toDomain()
    }

    /**
     * Returns aggregated statistics for the given calendar [month] and [year].
     *
     * Calls `GET /api/stats/monthly?month=<1-12>&year=<YYYY>`.
     */
    suspend fun getMonthlyStats(month: Int, year: Int): MonthlyStats = retrying {
        val token = tokenProvider()
        httpClient.get("$backendBaseUrl/api/stats/monthly") {
            bearerAuth(token)
            url.parameters.append("month", month.toString())
            url.parameters.append("year", year.toString())
        }.also { it.expectSuccess() }
            .body<MonthlyStatsDTO>()
            .toDomain()
    }

    /**
     * Returns all-time statistics for the authenticated user.
     *
     * Fetches `GET /api/stats/total` and `GET /api/stats/streak` **in parallel**
     * using [coroutineScope], then merges the results into a single [TotalStats].
     *
     * @param userId The authenticated user's ID (not included in the response body).
     */
    suspend fun getTotalStats(userId: String): TotalStats = coroutineScope {
        val totalDeferred = async { fetchTotalStats() }
        val streakDeferred = async { fetchStreak() }
        val total = totalDeferred.await()
        val streak = streakDeferred.await()
        total.toDomain(
            userId = userId,
            currentStreakDays = streak.currentStreak,
            longestStreakDays = streak.longestStreak,
        )
    }

    /**
     * Returns the current and longest workout streak for the authenticated user.
     *
     * Calls `GET /api/stats/streak`.
     */
    suspend fun getStreak(): StreakDTO = retrying {
        fetchStreak()
    }

    // =========================================================================
    // Username API
    // =========================================================================

    /**
     * Checks whether [username] is available (not taken by another user).
     *
     * Calls `GET /api/users/username/check?username=<username>`.
     *
     * @return [UsernameCheckResponse] with [available] = true if the username is free.
     */
    suspend fun checkUsernameAvailability(username: String): UsernameCheckResponse = retrying {
        val token = tokenProvider()
        httpClient.get("$backendBaseUrl/api/users/username/check") {
            bearerAuth(token)
            url.parameters.append("username", username)
        }.also { it.expectSuccess() }
            .body<UsernameCheckResponse>()
    }

    /**
     * Sets the username for the currently authenticated user.
     *
     * Calls `PATCH /api/users/username`.
     *
     * @return The username that was set.
     * @throws ApiException if the username is taken (409) or invalid (400).
     */
    suspend fun setUsername(request: SetUsernameRequest): String = retrying {
        val token = tokenProvider()
        httpClient.patch("$backendBaseUrl/api/users/username") {
            bearerAuth(token)
            contentType(ContentType.Application.Json)
            setBody(request)
        }.also { it.expectSuccess() }
            .body<com.pushup.data.api.dto.SetUsernameResponse>()
            .username
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private suspend fun fetchTotalStats(): TotalStatsDTO = retrying {
        val token = tokenProvider()
        httpClient.get("$backendBaseUrl/api/stats/total") {
            bearerAuth(token)
        }.also { it.expectSuccess() }
            .body<TotalStatsDTO>()
    }

    private suspend fun fetchStreak(): StreakDTO = retrying {
        val token = tokenProvider()
        httpClient.get("$backendBaseUrl/api/stats/streak") {
            bearerAuth(token)
        }.also { it.expectSuccess() }
            .body<StreakDTO>()
    }
}
