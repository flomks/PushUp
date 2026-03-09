package com.pushup.domain.model

/**
 * Aggregated push-up activity statistics for a friend over a given time period.
 *
 * Returned by GET /api/friends/{id}/stats?period=day|week|month.
 *
 * @property friendId            UUID of the friend whose stats are returned.
 * @property period              The requested period ("day", "week", or "month").
 * @property dateFrom            ISO-8601 date string for the start of the period (inclusive).
 * @property dateTo              ISO-8601 date string for the end of the period (inclusive).
 * @property pushupCount         Total push-ups performed by the friend in the period.
 * @property totalSessions       Number of completed workout sessions in the period.
 * @property totalEarnedSeconds  Total screen-time credits earned in the period (seconds).
 * @property averageQuality      Average form-quality score across all sessions (0.0 - 1.0),
 *                               null when no sessions exist.
 */
data class FriendActivityStats(
    val friendId: String,
    val period: String,
    val dateFrom: String,
    val dateTo: String,
    val pushupCount: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageQuality: Double?,
)
