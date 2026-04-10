package com.sinura.dto

import kotlinx.serialization.Serializable

/**
 * Supported time periods for the friend activity stats endpoint.
 */
enum class StatsPeriod {
    day,
    week,
    month,
    ;

    companion object {
        /**
         * Parses the `?period=` query parameter value (case-insensitive).
         * Returns null when the value is unrecognised.
         */
        fun fromQueryParam(value: String?): StatsPeriod? = when (value?.lowercase()) {
            "day"   -> day
            "week"  -> week
            "month" -> month
            else    -> null
        }
    }
}

/**
 * Date range covered by a friend activity stats response.
 *
 * @property from ISO-8601 date string for the start of the period (inclusive), e.g. "2026-03-09"
 * @property to   ISO-8601 date string for the end of the period (inclusive), e.g. "2026-03-09"
 */
@Serializable
data class DateRangeDTO(
    val from: String,
    val to: String,
)

/**
 * Activity statistics for a friend over a given time period.
 *
 * Returned by GET /api/friends/{id}/stats?period=day|week|month.
 *
 * @property friendId           UUID of the friend whose stats are returned.
 * @property period             The requested period ("day", "week", or "month").
 * @property dateRange          The calendar range covered by this response.
 * @property activityPoints     Unified activity score across all workout types.
 * @property pushupCount        Push-up count retained for backwards compatibility.
 * @property totalSessions      Number of completed workout sessions in the period.
 * @property totalEarnedSeconds Total screen-time credits earned in the period (seconds).
 * @property averageQuality     Average form-quality score across all sessions (0.0 - 1.0),
 *                              null when no sessions exist.
 * @property currentStreak      Current consecutive-day workout streak (days).
 * @property friendLevel         Current XP level of the friend (1-based).
 */
@Serializable
data class FriendActivityStatsDTO(
    val friendId: String,
    val period: String,
    val dateRange: DateRangeDTO,
    val activityPoints: Int,
    val pushupCount: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageQuality: Double?,
    val currentStreak: Int = 0,
    val friendLevel: Int = 1,
)

@Serializable
data class FriendActivityDayDTO(
    val date: String,
    val activityPoints: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
)

@Serializable
data class FriendMonthlyActivityDTO(
    val friendId: String,
    val month: Int,
    val year: Int,
    val days: List<FriendActivityDayDTO>,
    val activeDays: Int,
    val totalSessions: Int,
    val totalActivityPoints: Int,
    val totalEarnedSeconds: Long,
)

@Serializable
data class FriendExerciseLevelDTO(
    val exerciseTypeId: String,
    val level: Int,
    val totalXp: Long,
    val xpIntoLevel: Long,
    val xpRequiredForNextLevel: Long,
    val levelProgress: Double,
)

@Serializable
data class FriendLevelDetailsDTO(
    val friendId: String,
    val level: Int,
    val totalXp: Long,
    val xpIntoLevel: Long,
    val xpRequiredForNextLevel: Long,
    val levelProgress: Double,
    val exerciseLevels: List<FriendExerciseLevelDTO>,
)
