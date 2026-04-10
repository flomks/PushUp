package com.sinura.domain.model

/**
 * Aggregated activity statistics for a friend over a given time period.
 *
 * Returned by GET /api/friends/{id}/stats?period=day|week|month.
 *
 * @property friendId            UUID of the friend whose stats are returned.
 * @property period              The requested period ("day", "week", or "month").
 * @property dateFrom            ISO-8601 date string for the start of the period (inclusive).
 * @property dateTo              ISO-8601 date string for the end of the period (inclusive).
 * @property activityPoints      Unified activity score across all workout types.
 * @property pushupCount         Push-up count retained for backwards compatibility.
 * @property totalSessions       Number of completed workout sessions in the period.
 * @property totalEarnedSeconds  Total screen-time credits earned in the period (seconds).
 * @property averageQuality      Average form-quality score across all sessions (0.0 - 1.0),
 *                               null when no sessions exist.
 * @property currentStreak       Current consecutive-day workout streak (days).
 * @property friendLevel          Current XP level of the friend (1-based).
 */
data class FriendActivityStats(
    val friendId: String,
    val period: String,
    val dateFrom: String,
    val dateTo: String,
    val activityPoints: Int,
    val pushupCount: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageQuality: Double?,
    val currentStreak: Int = 0,
    val friendLevel: Int = 1,
)

data class FriendActivityDay(
    val date: String,
    val activityPoints: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
)

data class FriendMonthlyActivity(
    val friendId: String,
    val month: Int,
    val year: Int,
    val days: List<FriendActivityDay>,
    val activeDays: Int,
    val totalSessions: Int,
    val totalActivityPoints: Int,
    val totalEarnedSeconds: Long,
)

data class FriendExerciseLevel(
    val exerciseTypeId: String,
    val level: Int,
    val totalXp: Long,
    val xpIntoLevel: Long,
    val xpRequiredForNextLevel: Long,
    val levelProgress: Double,
)

data class FriendLevelDetails(
    val friendId: String,
    val level: Int,
    val totalXp: Long,
    val xpIntoLevel: Long,
    val xpRequiredForNextLevel: Long,
    val levelProgress: Double,
    val exerciseLevels: List<FriendExerciseLevel>,
)
