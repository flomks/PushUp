package com.pushup.domain.model

import kotlinx.datetime.LocalDate
import kotlinx.serialization.Serializable

/**
 * Aggregated statistics for a single day.
 *
 * @property date The calendar date these stats cover.
 * @property totalPushUps Total push-ups completed on this day.
 * @property totalSessions Number of workout sessions on this day.
 * @property totalEarnedSeconds Total screen-time credits earned on this day (in seconds).
 * @property averageQuality Average quality score across all sessions (0.0 - 1.0).
 */
@Serializable
data class DailyStats(
    val date: LocalDate,
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageQuality: Float,
)

/**
 * Aggregated statistics for a calendar week, with a per-day breakdown.
 *
 * @property weekStartDate The first day (Monday) of the week.
 * @property totalPushUps Total push-ups completed during the week.
 * @property totalSessions Number of workout sessions during the week.
 * @property totalEarnedSeconds Total screen-time credits earned during the week (in seconds).
 * @property dailyBreakdown Per-day statistics for each day of the week.
 */
@Serializable
data class WeeklyStats(
    val weekStartDate: LocalDate,
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val dailyBreakdown: List<DailyStats>,
)

/**
 * Aggregated statistics for a calendar month, with a per-week breakdown.
 *
 * @property month The month number (1-12).
 * @property year The four-digit year.
 * @property totalPushUps Total push-ups completed during the month.
 * @property totalSessions Number of workout sessions during the month.
 * @property totalEarnedSeconds Total screen-time credits earned during the month (in seconds).
 * @property weeklyBreakdown Per-week statistics for each week of the month.
 */
@Serializable
data class MonthlyStats(
    val month: Int,
    val year: Int,
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val weeklyBreakdown: List<WeeklyStats>,
)
