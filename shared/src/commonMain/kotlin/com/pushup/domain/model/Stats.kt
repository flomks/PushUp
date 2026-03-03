package com.pushup.domain.model

import kotlinx.datetime.LocalDate
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

/**
 * Aggregated statistics for a single day.
 *
 * @property date The calendar date these stats cover.
 * @property totalPushUps Total push-ups completed on this day.
 * @property totalSessions Number of workout sessions on this day.
 * @property totalEarnedSeconds Total screen-time credits earned on this day (in seconds).
 * @property averageQuality Average quality score across all sessions (0.0 - 1.0).
 * @property averagePushUpsPerSession Average push-ups per session, or `0f` when no sessions exist.
 * @property bestSession Push-up count of the best (highest-count) session, or `0` when no sessions exist.
 */
@Serializable
data class DailyStats(
    val date: LocalDate,
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageQuality: Float,
    val averagePushUpsPerSession: Float,
    val bestSession: Int,
) {
    init {
        require(totalPushUps >= 0) { "DailyStats.totalPushUps must be >= 0, was $totalPushUps" }
        require(totalSessions >= 0) { "DailyStats.totalSessions must be >= 0, was $totalSessions" }
        require(totalEarnedSeconds >= 0) {
            "DailyStats.totalEarnedSeconds must be >= 0, was $totalEarnedSeconds"
        }
        require(averageQuality in 0f..1f) {
            "DailyStats.averageQuality must be in [0, 1], was $averageQuality"
        }
        require(averagePushUpsPerSession >= 0f) {
            "DailyStats.averagePushUpsPerSession must be >= 0, was $averagePushUpsPerSession"
        }
        require(bestSession >= 0) { "DailyStats.bestSession must be >= 0, was $bestSession" }
    }

    /** `true` when at least one session was completed on this day. */
    @Transient
    val hasActivity: Boolean = totalSessions > 0
}

/**
 * Aggregated statistics for a calendar week, with a per-day breakdown.
 *
 * @property weekStartDate The first day (Monday) of the week.
 * @property totalPushUps Total push-ups completed during the week.
 * @property totalSessions Number of workout sessions during the week.
 * @property totalEarnedSeconds Total screen-time credits earned during the week (in seconds).
 * @property averagePushUpsPerSession Average push-ups per session across the week, or `0f` when no sessions exist.
 * @property bestSession Push-up count of the best session in the week, or `0` when no sessions exist.
 * @property dailyBreakdown Per-day statistics for each day of the week (always 7 entries).
 */
@Serializable
data class WeeklyStats(
    val weekStartDate: LocalDate,
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averagePushUpsPerSession: Float,
    val bestSession: Int,
    val dailyBreakdown: List<DailyStats>,
) {
    init {
        require(totalPushUps >= 0) { "WeeklyStats.totalPushUps must be >= 0, was $totalPushUps" }
        require(totalSessions >= 0) { "WeeklyStats.totalSessions must be >= 0, was $totalSessions" }
        require(totalEarnedSeconds >= 0) {
            "WeeklyStats.totalEarnedSeconds must be >= 0, was $totalEarnedSeconds"
        }
        require(averagePushUpsPerSession >= 0f) {
            "WeeklyStats.averagePushUpsPerSession must be >= 0, was $averagePushUpsPerSession"
        }
        require(bestSession >= 0) { "WeeklyStats.bestSession must be >= 0, was $bestSession" }
    }

    /** Number of days in the week that had at least one session. */
    @Transient
    val activeDays: Int = dailyBreakdown.count { it.hasActivity }

    /** Average quality across all days that had activity, or `0f` if none. */
    @Transient
    val averageQuality: Float = dailyBreakdown
        .filter { it.hasActivity }
        .map { it.averageQuality }
        .average()
        .toFloat()
        .takeIf { !it.isNaN() } ?: 0f
}

/**
 * Aggregated statistics for a calendar month, with a per-week breakdown.
 *
 * @property month The month number (1-12).
 * @property year The four-digit year.
 * @property totalPushUps Total push-ups completed during the month.
 * @property totalSessions Number of workout sessions during the month.
 * @property totalEarnedSeconds Total screen-time credits earned during the month (in seconds).
 * @property averagePushUpsPerSession Average push-ups per session across the month, or `0f` when no sessions exist.
 * @property bestSession Push-up count of the best session in the month, or `0` when no sessions exist.
 * @property weeklyBreakdown Per-week statistics for each week of the month.
 */
@Serializable
data class MonthlyStats(
    val month: Int,
    val year: Int,
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averagePushUpsPerSession: Float,
    val bestSession: Int,
    val weeklyBreakdown: List<WeeklyStats>,
) {
    init {
        require(month in 1..12) { "MonthlyStats.month must be in [1, 12], was $month" }
        require(year > 0) { "MonthlyStats.year must be > 0, was $year" }
        require(totalPushUps >= 0) { "MonthlyStats.totalPushUps must be >= 0, was $totalPushUps" }
        require(totalSessions >= 0) { "MonthlyStats.totalSessions must be >= 0, was $totalSessions" }
        require(totalEarnedSeconds >= 0) {
            "MonthlyStats.totalEarnedSeconds must be >= 0, was $totalEarnedSeconds"
        }
        require(averagePushUpsPerSession >= 0f) {
            "MonthlyStats.averagePushUpsPerSession must be >= 0, was $averagePushUpsPerSession"
        }
        require(bestSession >= 0) { "MonthlyStats.bestSession must be >= 0, was $bestSession" }
    }

    /** Number of active weeks (weeks with at least one session). */
    @Transient
    val activeWeeks: Int = weeklyBreakdown.count { it.totalSessions > 0 }

    /** Average quality across all active weeks, or `0f` if none. */
    @Transient
    val averageQuality: Float = weeklyBreakdown
        .filter { it.totalSessions > 0 }
        .map { it.averageQuality }
        .average()
        .toFloat()
        .takeIf { !it.isNaN() } ?: 0f
}

/**
 * Aggregated lifetime statistics for a user (since app installation).
 *
 * @property userId Identifier of the user these stats belong to.
 * @property totalPushUps Total push-ups completed across all time.
 * @property totalSessions Total number of workout sessions completed.
 * @property totalEarnedSeconds Total screen-time credits earned across all time (in seconds).
 * @property totalSpentSeconds Total screen-time credits spent across all time (in seconds).
 * @property averageQuality Average quality score across all sessions (0.0 - 1.0).
 * @property averagePushUpsPerSession Average push-ups per session across all time, or `0f` when no sessions exist.
 * @property bestSession Push-up count of the best (highest-count) session ever, or `0` when no sessions exist.
 * @property currentStreakDays Number of consecutive days ending on today (or yesterday) with at least one session.
 *   Resets to `0` if the last workout day is older than yesterday.
 * @property longestStreakDays Longest-ever consecutive-day streak.
 */
@Serializable
data class TotalStats(
    val userId: String,
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val totalSpentSeconds: Long,
    val averageQuality: Float,
    val averagePushUpsPerSession: Float,
    val bestSession: Int,
    val currentStreakDays: Int,
    val longestStreakDays: Int,
) {
    init {
        require(userId.isNotBlank()) { "TotalStats.userId must not be blank" }
        require(totalPushUps >= 0) { "TotalStats.totalPushUps must be >= 0, was $totalPushUps" }
        require(totalSessions >= 0) { "TotalStats.totalSessions must be >= 0, was $totalSessions" }
        require(totalEarnedSeconds >= 0) {
            "TotalStats.totalEarnedSeconds must be >= 0, was $totalEarnedSeconds"
        }
        require(totalSpentSeconds >= 0) {
            "TotalStats.totalSpentSeconds must be >= 0, was $totalSpentSeconds"
        }
        require(averageQuality in 0f..1f) {
            "TotalStats.averageQuality must be in [0, 1], was $averageQuality"
        }
        require(averagePushUpsPerSession >= 0f) {
            "TotalStats.averagePushUpsPerSession must be >= 0, was $averagePushUpsPerSession"
        }
        require(bestSession >= 0) { "TotalStats.bestSession must be >= 0, was $bestSession" }
        require(currentStreakDays >= 0) {
            "TotalStats.currentStreakDays must be >= 0, was $currentStreakDays"
        }
        require(longestStreakDays >= 0) {
            "TotalStats.longestStreakDays must be >= 0, was $longestStreakDays"
        }
        require(longestStreakDays >= currentStreakDays) {
            "TotalStats.longestStreakDays ($longestStreakDays) must be >= currentStreakDays ($currentStreakDays)"
        }
    }

    /** Remaining credit balance (earned minus spent). */
    @Transient
    val availableSeconds: Long = totalEarnedSeconds - totalSpentSeconds
}
