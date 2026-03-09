package com.pushup.service

import com.pushup.models.StreakResponse
import com.pushup.models.TimeCreditResponse
import com.pushup.models.UserDataResponse
import com.pushup.models.UserResponse
import com.pushup.models.UserStatsResponse
import com.pushup.plugins.TimeCredits
import com.pushup.plugins.Users
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.isNotNull
import org.jetbrains.exposed.sql.and
import org.jetbrains.exposed.sql.avg
import org.jetbrains.exposed.sql.count
import org.jetbrains.exposed.sql.max
import org.jetbrains.exposed.sql.min
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.sum
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID

/**
 * Aggregates all user-facing data into a single [UserDataResponse].
 *
 * Executes the following queries:
 * 1. User profile from `public.users`.
 * 2. All-time workout statistics from `public.workout_sessions`
 *    (only completed sessions where `ended_at IS NOT NULL`).
 * 3. Time-credit balance from `public.time_credits`.
 * 4. Streak information (current + longest) via [StatsService.getStreak].
 *
 * This service is intentionally read-only and has no side effects.
 */
class UserDataService(
    private val statsService: StatsService = StatsService(),
) {

    // Reusable aggregate expressions (created once, shared across calls)
    private val pushUpSum    = WorkoutSessions.pushUpCount.sum()
    private val creditsSum   = WorkoutSessions.earnedTimeCredits.sum()
    private val qualityAvg   = WorkoutSessions.quality.avg()
    private val sessionCount = WorkoutSessions.id.count()
    private val bestSession  = WorkoutSessions.pushUpCount.max()
    private val firstWorkout = WorkoutSessions.startedAt.min()

    /**
     * Returns the full user data overview for [userId].
     *
     * @return [UserDataResponse] or `null` when the user profile is not found.
     */
    suspend fun getUserData(userId: UUID): UserDataResponse? {

        // Streak opens its own transaction internally -- call it outside the
        // main transaction to avoid nesting.
        val streakDTO = statsService.getStreak(userId)

        return newSuspendedTransaction {

            // ----------------------------------------------------------------
            // 1. User profile
            // ----------------------------------------------------------------
            val userRow = Users.selectAll()
                .where { Users.id eq userId }
                .singleOrNull()
                ?: return@newSuspendedTransaction null

            val userResponse = UserResponse(
                id          = userRow[Users.id].toString(),
                email       = userRow[Users.email],
                displayName = userRow[Users.displayName],
                avatarUrl   = userRow[Users.avatarUrl],
                createdAt   = userRow[Users.createdAt].format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
                updatedAt   = userRow[Users.updatedAt].format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
            )

            // ----------------------------------------------------------------
            // 2. All-time workout statistics (completed sessions only)
            // ----------------------------------------------------------------
            val statsRow = WorkoutSessions
                .select(pushUpSum, creditsSum, qualityAvg, sessionCount, bestSession, firstWorkout)
                .where {
                    (WorkoutSessions.userId eq userId) and
                        WorkoutSessions.endedAt.isNotNull()
                }
                .firstOrNull()

            val totalPushUps    = statsRow?.get(pushUpSum) ?: 0
            val totalSessions   = statsRow?.get(sessionCount)?.toInt() ?: 0
            val earnedFromStats = (statsRow?.get(creditsSum) ?: 0L).toLong()
            val firstInstant    = statsRow?.get(firstWorkout)

            val statsResponse = UserStatsResponse(
                totalPushUps             = totalPushUps,
                totalSessions            = totalSessions,
                totalEarnedSeconds       = earnedFromStats,
                averageQuality           = statsRow?.get(qualityAvg)?.toDouble(),
                averagePushUpsPerSession = if (totalSessions > 0) totalPushUps.toDouble() / totalSessions else null,
                bestSessionPushUps       = statsRow?.get(bestSession),
                firstWorkoutDate         = firstInstant
                    ?.atZone(ZoneOffset.UTC)
                    ?.toLocalDate()
                    ?.format(DateTimeFormatter.ISO_LOCAL_DATE),
            )

            // ----------------------------------------------------------------
            // 3. Time-credit balance
            // ----------------------------------------------------------------
            val creditRow = TimeCredits.selectAll()
                .where { TimeCredits.userId eq userId }
                .singleOrNull()

            val totalEarned = creditRow?.get(TimeCredits.totalEarnedSeconds) ?: earnedFromStats
            val totalSpent  = creditRow?.get(TimeCredits.totalSpentSeconds) ?: 0L
            val available   = (totalEarned - totalSpent).coerceAtLeast(0L)

            val timeCreditResponse = TimeCreditResponse(
                totalEarnedSeconds = totalEarned,
                totalSpentSeconds  = totalSpent,
                availableSeconds   = available,
            )

            // ----------------------------------------------------------------
            // 4. Streak (computed above, outside this transaction)
            // ----------------------------------------------------------------
            val streakResponse = StreakResponse(
                currentStreak   = streakDTO.currentStreak,
                longestStreak   = streakDTO.longestStreak,
                lastWorkoutDate = streakDTO.lastWorkoutDate,
            )

            UserDataResponse(
                user       = userResponse,
                stats      = statsResponse,
                timeCredit = timeCreditResponse,
                streak     = streakResponse,
            )
        }
    }
}
