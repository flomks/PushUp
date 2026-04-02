package com.pushup.dto

import kotlinx.serialization.Serializable

/**
 * Per-day activity data for the heatmap endpoint.
 *
 * @property date ISO-8601 date string, e.g. "2026-04-02"
 * @property totalSessions Number of completed sessions (all workout types).
 * @property totalEarnedSeconds Total screen-time credits earned on this day.
 */
@Serializable
data class ActivityDayDTO(
    val date: String,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
)

/**
 * Monthly heatmap response containing one entry per day.
 *
 * @property month Month number (1-12).
 * @property year Four-digit year.
 * @property days Per-day activity data (one entry per calendar day in the month).
 * @property activeDays Number of days with at least one session.
 * @property totalSessions Total sessions across the month.
 * @property totalEarnedSeconds Total earned credits across the month.
 */
@Serializable
data class ActivityMonthlyDTO(
    val month: Int,
    val year: Int,
    val days: List<ActivityDayDTO>,
    val activeDays: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
)

/**
 * Unified activity streak (across all workout types).
 *
 * @property currentStreak Consecutive days ending today/yesterday with at least one workout.
 * @property longestStreak All-time longest streak in days.
 * @property lastActivityDate ISO-8601 date of the most recent completed activity, null when none.
 */
@Serializable
data class ActivityStreakDTO(
    val currentStreak: Int,
    val longestStreak: Int,
    val lastActivityDate: String?,
)
