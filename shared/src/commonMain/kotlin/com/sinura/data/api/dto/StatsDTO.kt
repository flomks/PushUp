package com.sinura.data.api.dto

import com.sinura.domain.model.DailyStats
import com.sinura.domain.model.MonthlyStats
import com.sinura.domain.model.TotalStats
import com.sinura.domain.model.WeeklyStats
import kotlinx.datetime.LocalDate
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// =============================================================================
// Stats DTOs (client-side mirror of the Ktor backend's response shapes)
// =============================================================================

/**
 * Statistics for a single calendar day, as returned by `GET /api/stats/daily`.
 *
 * @property date               ISO-8601 date string, e.g. "2026-03-02".
 * @property totalPushUps       Total push-ups performed across all sessions on this day.
 * @property totalSessions      Number of completed workout sessions on this day.
 * @property totalEarnedSeconds Total screen-time credits earned (seconds).
 * @property averageQuality     Average form-quality score (0.0 - 1.0), or `null` when no sessions.
 */
@Serializable
data class DailyStatsDTO(
    @SerialName("date")                 val date: String,
    @SerialName("totalPushUps")         val totalPushUps: Int,
    @SerialName("totalSessions")        val totalSessions: Int,
    @SerialName("totalEarnedSeconds")   val totalEarnedSeconds: Long,
    @SerialName("averageQuality")       val averageQuality: Double?,
)

/**
 * Statistics for a calendar week (Monday - Sunday), as returned by
 * `GET /api/stats/weekly`.
 *
 * @property weekStart          ISO-8601 date of the Monday that starts this week.
 * @property weekEnd            ISO-8601 date of the Sunday that ends this week.
 * @property totalPushUps       Aggregated push-ups for the whole week.
 * @property totalSessions      Aggregated sessions for the whole week.
 * @property totalEarnedSeconds Aggregated earned credits for the whole week (seconds).
 * @property averageQuality     Average quality across all sessions in the week, or `null`.
 * @property dailyBreakdown     One [DailyStatsDTO] entry per day of the week (always 7 entries).
 */
@Serializable
data class WeeklyStatsDTO(
    @SerialName("weekStart")            val weekStart: String,
    @SerialName("weekEnd")              val weekEnd: String,
    @SerialName("totalPushUps")         val totalPushUps: Int,
    @SerialName("totalSessions")        val totalSessions: Int,
    @SerialName("totalEarnedSeconds")   val totalEarnedSeconds: Long,
    @SerialName("averageQuality")       val averageQuality: Double?,
    @SerialName("dailyBreakdown")       val dailyBreakdown: List<DailyStatsDTO>,
)

/**
 * Statistics for a calendar month, as returned by `GET /api/stats/monthly`.
 *
 * @property month              Month number (1-12).
 * @property year               Four-digit year.
 * @property totalPushUps       Aggregated push-ups for the whole month.
 * @property totalSessions      Aggregated sessions for the whole month.
 * @property totalEarnedSeconds Aggregated earned credits for the whole month (seconds).
 * @property averageQuality     Average quality across all sessions in the month, or `null`.
 * @property weeklyBreakdown    One [WeeklyStatsDTO] per ISO week that overlaps with this month.
 */
@Serializable
data class MonthlyStatsDTO(
    @SerialName("month")                val month: Int,
    @SerialName("year")                 val year: Int,
    @SerialName("totalPushUps")         val totalPushUps: Int,
    @SerialName("totalSessions")        val totalSessions: Int,
    @SerialName("totalEarnedSeconds")   val totalEarnedSeconds: Long,
    @SerialName("averageQuality")       val averageQuality: Double?,
    @SerialName("weeklyBreakdown")      val weeklyBreakdown: List<WeeklyStatsDTO>,
)

/**
 * All-time statistics since the user first installed the app, as returned by
 * `GET /api/stats/total`.
 *
 * @property totalPushUps               Grand total push-ups ever performed.
 * @property totalSessions              Grand total completed sessions.
 * @property totalEarnedSeconds         Grand total screen-time credits earned (seconds).
 * @property averageQuality             Average quality across all sessions, or `null`.
 * @property averagePushUpsPerSession   Average push-ups per completed session, or `null`.
 * @property bestSessionPushUps         Highest push-up count in a single session, or `null`.
 * @property firstWorkoutDate           ISO-8601 date of the very first workout, or `null`.
 */
@Serializable
data class TotalStatsDTO(
    @SerialName("totalPushUps")             val totalPushUps: Int,
    @SerialName("totalSessions")            val totalSessions: Int,
    @SerialName("totalEarnedSeconds")       val totalEarnedSeconds: Long,
    @SerialName("averageQuality")           val averageQuality: Double?,
    @SerialName("averagePushUpsPerSession") val averagePushUpsPerSession: Double?,
    @SerialName("bestSessionPushUps")       val bestSessionPushUps: Int?,
    @SerialName("firstWorkoutDate")         val firstWorkoutDate: String?,
)

/**
 * Current workout streak information, as returned by `GET /api/stats/streak`.
 *
 * @property currentStreak   Consecutive days (up to today) with at least one workout.
 * @property longestStreak   All-time longest streak in days.
 * @property lastWorkoutDate ISO-8601 date of the most recent completed workout, or `null`.
 */
@Serializable
data class StreakDTO(
    @SerialName("currentStreak")    val currentStreak: Int,
    @SerialName("longestStreak")    val longestStreak: Int,
    @SerialName("lastWorkoutDate")  val lastWorkoutDate: String?,
)

// =============================================================================
// Domain model mappers
// =============================================================================

/**
 * Converts a [DailyStatsDTO] from the Ktor backend into a [DailyStats] domain model.
 *
 * The [DailyStats] domain model uses [Float] for quality scores while the DTO
 * uses [Double] (JSON default). The conversion is safe because quality is always
 * in [0.0, 1.0].
 */
fun DailyStatsDTO.toDomain(): DailyStats = DailyStats(
    date = LocalDate.parse(date),
    totalActivityXp = totalPushUps.toLong(),
    totalSessions = totalSessions,
    totalEarnedSeconds = totalEarnedSeconds,
    averageQuality = averageQuality?.toFloat() ?: 0f,
    averageActivityXpPerSession = if (totalSessions > 0) totalPushUps.toFloat() / totalSessions else 0f,
    bestSessionActivityXp = 0L, // Not provided by the daily endpoint; use 0 as a safe default.
)

/**
 * Converts a [WeeklyStatsDTO] from the Ktor backend into a [WeeklyStats] domain model.
 */
fun WeeklyStatsDTO.toDomain(): WeeklyStats = WeeklyStats(
    weekStartDate = LocalDate.parse(weekStart),
    totalActivityXp = totalPushUps.toLong(),
    totalSessions = totalSessions,
    totalEarnedSeconds = totalEarnedSeconds,
    averageActivityXpPerSession = if (totalSessions > 0) totalPushUps.toFloat() / totalSessions else 0f,
    bestSessionActivityXp = 0L, // Not provided by the weekly endpoint; use 0 as a safe default.
    dailyBreakdown = dailyBreakdown.map { it.toDomain() },
)

/**
 * Converts a [MonthlyStatsDTO] from the Ktor backend into a [MonthlyStats] domain model.
 */
fun MonthlyStatsDTO.toDomain(): MonthlyStats = MonthlyStats(
    month = month,
    year = year,
    totalActivityXp = totalPushUps.toLong(),
    totalSessions = totalSessions,
    totalEarnedSeconds = totalEarnedSeconds,
    averageActivityXpPerSession = if (totalSessions > 0) totalPushUps.toFloat() / totalSessions else 0f,
    bestSessionActivityXp = 0L, // Not provided by the monthly endpoint; use 0 as a safe default.
    weeklyBreakdown = weeklyBreakdown.map { it.toDomain() },
)

/**
 * Converts a [TotalStatsDTO] from the Ktor backend into a [TotalStats] domain model.
 *
 * @param userId The authenticated user's ID (not included in the DTO response body).
 * @param currentStreakDays The current streak from the separate streak endpoint.
 * @param longestStreakDays The longest streak from the separate streak endpoint.
 */
fun TotalStatsDTO.toDomain(
    userId: String,
    currentStreakDays: Int = 0,
    longestStreakDays: Int = 0,
): TotalStats = TotalStats(
    userId = userId,
    totalActivityXp = totalPushUps.toLong(),
    totalSessions = totalSessions,
    totalEarnedSeconds = totalEarnedSeconds,
    totalSpentSeconds = 0L, // Not tracked server-side in the stats endpoint.
    averageQuality = averageQuality?.toFloat() ?: 0f,
    averageActivityXpPerSession = averagePushUpsPerSession?.toFloat() ?: 0f,
    bestSessionActivityXp = bestSessionPushUps?.toLong() ?: 0L,
    currentStreakDays = currentStreakDays,
    longestStreakDays = longestStreakDays,
)
