package com.pushup.models

import kotlinx.serialization.Serializable

/**
 * Combined user data overview returned by GET /api/user/data.
 *
 * Aggregates the user's profile, all-time workout statistics, time-credit
 * balance, and streak information into a single response so that the client
 * can populate a dashboard screen with one HTTP request.
 *
 * @property user          The authenticated user's profile.
 * @property stats         All-time workout statistics.
 * @property timeCredit    Current time-credit balance.
 * @property streak        Current and longest workout streak.
 */
@Serializable
data class UserDataResponse(
    val user: UserResponse,
    val stats: UserStatsResponse,
    val timeCredit: TimeCreditResponse,
    val streak: StreakResponse,
)

/**
 * All-time workout statistics summary.
 *
 * @property totalPushUps               Grand total push-ups ever performed.
 * @property totalSessions              Grand total completed workout sessions.
 * @property totalEarnedSeconds         Grand total screen-time credits earned (seconds).
 * @property averageQuality             Average form-quality score across all sessions (0.0 - 1.0),
 *                                      null when no sessions exist.
 * @property averagePushUpsPerSession   Average push-ups per completed session, null when no sessions.
 * @property bestSessionPushUps         Highest push-up count in a single session, null when no sessions.
 * @property firstWorkoutDate           ISO-8601 date of the very first workout, null when no sessions.
 */
@Serializable
data class UserStatsResponse(
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageQuality: Double?,
    val averagePushUpsPerSession: Double?,
    val bestSessionPushUps: Int?,
    val firstWorkoutDate: String?,
)

/**
 * Time-credit balance for the authenticated user.
 *
 * @property totalEarnedSeconds  Total seconds earned through workouts (ever).
 * @property totalSpentSeconds   Total seconds spent as screen-time (ever).
 * @property availableSeconds    Remaining balance: earned minus spent (always >= 0).
 */
@Serializable
data class TimeCreditResponse(
    val totalEarnedSeconds: Long,
    val totalSpentSeconds: Long,
    val availableSeconds: Long,
)

/**
 * Workout streak information.
 *
 * @property currentStreak   Consecutive calendar days (up to today) with at least one workout.
 *                           0 when the last workout was more than one day ago.
 * @property longestStreak   All-time longest streak in days.
 * @property lastWorkoutDate ISO-8601 date of the most recent completed workout, null when none.
 */
@Serializable
data class StreakResponse(
    val currentStreak: Int,
    val longestStreak: Int,
    val lastWorkoutDate: String?,
)
