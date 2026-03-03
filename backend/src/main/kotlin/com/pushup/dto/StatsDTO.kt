package com.pushup.dto

import kotlinx.serialization.Serializable

/**
 * Statistics for a single calendar day.
 *
 * @property date          ISO-8601 date string, e.g. "2026-03-02"
 * @property totalPushUps  Total push-ups performed across all sessions on this day
 * @property totalSessions Number of completed workout sessions on this day
 * @property totalEarnedSeconds Total screen-time credits earned (seconds)
 * @property averageQuality Average form-quality score across all sessions (0.0 - 1.0),
 *                          null when no sessions exist
 */
@Serializable
data class DailyStatsDTO(
    val date: String,
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageQuality: Double?,
)

/**
 * Statistics for a calendar week (Monday - Sunday).
 *
 * @property weekStart     ISO-8601 date of the Monday that starts this week, e.g. "2026-02-24"
 * @property weekEnd       ISO-8601 date of the Sunday that ends this week, e.g. "2026-03-02"
 * @property totalPushUps  Aggregated push-ups for the whole week
 * @property totalSessions Aggregated sessions for the whole week
 * @property totalEarnedSeconds Aggregated earned credits for the whole week (seconds)
 * @property averageQuality Average quality across all sessions in the week, null when empty
 * @property dailyBreakdown One [DailyStatsDTO] entry per day of the week (always 7 entries)
 */
@Serializable
data class WeeklyStatsDTO(
    val weekStart: String,
    val weekEnd: String,
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageQuality: Double?,
    val dailyBreakdown: List<DailyStatsDTO>,
)

/**
 * Statistics for a calendar month.
 *
 * @property month         Month number (1-12)
 * @property year          Four-digit year
 * @property totalPushUps  Aggregated push-ups for the whole month
 * @property totalSessions Aggregated sessions for the whole month
 * @property totalEarnedSeconds Aggregated earned credits for the whole month (seconds)
 * @property averageQuality Average quality across all sessions in the month, null when empty
 * @property weeklyBreakdown One [WeeklyStatsDTO] per ISO week that overlaps with this month
 */
@Serializable
data class MonthlyStatsDTO(
    val month: Int,
    val year: Int,
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageQuality: Double?,
    val weeklyBreakdown: List<WeeklyStatsDTO>,
)

/**
 * All-time statistics since the user first installed the app.
 *
 * @property totalPushUps           Grand total push-ups ever performed
 * @property totalSessions          Grand total completed sessions
 * @property totalEarnedSeconds     Grand total screen-time credits earned (seconds)
 * @property averageQuality         Average quality across all sessions ever, null when empty
 * @property averagePushUpsPerSession Average push-ups per completed session, null when empty
 * @property bestSessionPushUps     Highest push-up count in a single session, null when empty
 * @property firstWorkoutDate       ISO-8601 date of the very first workout, null when empty
 */
@Serializable
data class TotalStatsDTO(
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageQuality: Double?,
    val averagePushUpsPerSession: Double?,
    val bestSessionPushUps: Int?,
    val firstWorkoutDate: String?,
)

/**
 * Current workout streak information.
 *
 * @property currentStreak  Number of consecutive calendar days (up to and including today)
 *                          on which the user completed at least one workout.
 *                          0 means no workout today or yesterday.
 * @property longestStreak  All-time longest streak in days.
 * @property lastWorkoutDate ISO-8601 date of the most recent completed workout,
 *                           null when the user has never worked out.
 */
@Serializable
data class StreakDTO(
    val currentStreak: Int,
    val longestStreak: Int,
    val lastWorkoutDate: String?,
)
