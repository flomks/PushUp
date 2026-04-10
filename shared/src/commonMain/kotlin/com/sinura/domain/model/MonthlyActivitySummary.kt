package com.sinura.domain.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

/**
 * Activity summary for a calendar month, optimised for heatmap rendering.
 *
 * Contains one [ActivityDayStats] entry per day in the month (including
 * days with zero activity) so the UI can render a complete calendar grid
 * without gaps.
 *
 * @property month The month number (1-12).
 * @property year The four-digit year.
 * @property days Per-day activity stats. Always contains one entry per
 *   calendar day in the month (28-31 entries), sorted ascending.
 */
@Serializable
data class MonthlyActivitySummary(
    val month: Int,
    val year: Int,
    val days: List<ActivityDayStats>,
) {
    init {
        require(month in 1..12) { "MonthlyActivitySummary.month must be in [1, 12], was $month" }
        require(year > 0) { "MonthlyActivitySummary.year must be > 0, was $year" }
    }

    /** Number of days with at least one workout session. */
    @Transient
    val activeDays: Int = days.count { it.hasActivity }

    /** Total sessions across the entire month. */
    @Transient
    val totalSessions: Int = days.sumOf { it.totalSessions }

    /** Total earned seconds across the entire month. */
    @Transient
    val totalEarnedSeconds: Long = days.sumOf { it.totalEarnedSeconds }

    /** Average earned seconds per active day, or 0 if no active days. */
    @Transient
    val averageEarnedSecondsPerActiveDay: Long =
        if (activeDays > 0) totalEarnedSeconds / activeDays else 0L
}
