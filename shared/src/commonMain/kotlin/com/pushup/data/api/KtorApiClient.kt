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
 * ## Error handling
 * All HTTP and network errors are mapped to [ApiException] subclasses.
 * Transient errors are retried automatically (see [ApiClientBase.withRetry]).
 *
 * @property httpClient     Configured [HttpClient] (from [createHttpClient]).
 * @property backendBaseUrl Ktor backend base URL, e.g. `https://api.pushup.com`.
 * @property tokenProvider  Returns the current JWT access token.
 * @property maxRetries     Max retry attempts for transient errors (default 3).
 */
class KtorApiClient(
    private val httpClient: HttpClient,
    private val backendBaseUrl: String,
    private val tokenProvider: suspend () -> String,
    maxRetries: Int = 3,
) : ApiClientBase(maxRetries) {

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Returns aggregated statistics for a single calendar [date].
     *
     * Calls `GET /api/stats/daily?date=<YYYY-MM-DD>`.
     */
    suspend fun getDailyStats(date: LocalDate): DailyStats = withRetry {
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
    suspend fun getWeeklyStats(weekStart: LocalDate): WeeklyStats = withRetry {
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
    suspend fun getMonthlyStats(month: Int, year: Int): MonthlyStats = withRetry {
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
    suspend fun getStreak(): StreakDTO = withRetry {
        fetchStreak()
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private suspend fun fetchTotalStats(): TotalStatsDTO = withRetry {
        val token = tokenProvider()
        httpClient.get("$backendBaseUrl/api/stats/total") {
            bearerAuth(token)
        }.also { it.expectSuccess() }
            .body<TotalStatsDTO>()
    }

    private suspend fun fetchStreak(): StreakDTO = withRetry {
        val token = tokenProvider()
        httpClient.get("$backendBaseUrl/api/stats/streak") {
            bearerAuth(token)
        }.also { it.expectSuccess() }
            .body<StreakDTO>()
    }
}
