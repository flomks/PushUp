package com.pushup.service

import com.pushup.dto.DateRangeDTO
import com.pushup.dto.FriendActivityStatsDTO
import com.pushup.dto.StatsPeriod
import com.pushup.plugins.FriendshipStatus
import com.pushup.plugins.Friendships
import com.pushup.plugins.UserLevels
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.greaterEq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.isNotNull
import org.jetbrains.exposed.sql.SqlExpressionBuilder.less
import org.jetbrains.exposed.sql.and
import org.jetbrains.exposed.sql.avg
import org.jetbrains.exposed.sql.count
import org.jetbrains.exposed.sql.or
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.sum
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import java.util.UUID
import kotlin.math.floor
import kotlin.math.pow

/**
 * Result type for [FriendActivityStatsService.getStats].
 *
 * Using a sealed class keeps error handling explicit and avoids leaking
 * database details through uncaught exceptions.
 */
sealed class FriendActivityStatsResult {
    /** Stats were retrieved successfully. */
    data class Success(val stats: FriendActivityStatsDTO) : FriendActivityStatsResult()

    /**
     * The caller and the target user are not active friends.
     * The route handler must respond with 403 Forbidden.
     */
    object NotFriends : FriendActivityStatsResult()

    /** The target user does not exist in the database. */
    object FriendNotFound : FriendActivityStatsResult()
}

/**
 * Business logic for GET /api/friends/{id}/stats.
 *
 * Responsibilities:
 * 1. Verify that an ACCEPTED friendship exists between [callerId] and [friendId].
 * 2. Compute the date range for the requested [StatsPeriod].
 * 3. Aggregate push-up statistics from [WorkoutSessions] for [friendId] in that range.
 *
 * All database access is performed inside [newSuspendedTransaction] so that
 * Ktor's coroutine event loop is not blocked.
 *
 * The class and its public methods are `open` so that tests can create stub
 * subclasses without requiring a mocking framework.
 */
open class FriendActivityStatsService {

    /**
     * Returns activity statistics for [friendId] as seen by [callerId].
     *
     * @param callerId UUID of the authenticated user making the request.
     * @param friendId UUID of the friend whose stats are requested.
     * @param period   The time period to aggregate over.
     * @param today    Reference date for period calculation; injectable for tests.
     * @return [FriendActivityStatsResult] describing the outcome.
     */
    open suspend fun getStats(
        callerId: UUID,
        friendId: UUID,
        period: StatsPeriod,
        today: LocalDate = LocalDate.now(ZoneOffset.UTC),
    ): FriendActivityStatsResult = newSuspendedTransaction {

        // ------------------------------------------------------------------
        // 1. Verify an ACCEPTED friendship exists in either direction
        // ------------------------------------------------------------------
        val friendshipExists = Friendships.selectAll()
            .where {
                (Friendships.status eq FriendshipStatus.ACCEPTED) and (
                    (
                        (Friendships.requesterId eq callerId) and
                        (Friendships.receiverId  eq friendId)
                    ) or (
                        (Friendships.requesterId eq friendId) and
                        (Friendships.receiverId  eq callerId)
                    )
                )
            }
            .count() > 0

        if (!friendshipExists) {
            return@newSuspendedTransaction FriendActivityStatsResult.NotFriends
        }

        // ------------------------------------------------------------------
        // 2. Compute the date range for the requested period
        // ------------------------------------------------------------------
        val (from, to) = dateRangeFor(period, today)

        val fromInstant: Instant = from.atStartOfDay().toInstant(ZoneOffset.UTC)
        // toInstant is exclusive: start of the day AFTER the last day of the period
        val toInstant: Instant   = to.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)

        // ------------------------------------------------------------------
        // 3. Aggregate workout stats for the friend in the date range
        //
        // Reuse the same aggregate expression instances as StatsService to
        // avoid any Exposed ResultRow ambiguity.
        // ------------------------------------------------------------------
        val pushUpSum    = WorkoutSessions.pushUpCount.sum()
        val creditsSum   = WorkoutSessions.earnedTimeCredits.sum()
        val qualityAvg   = WorkoutSessions.quality.avg()
        val sessionCount = WorkoutSessions.id.count()

        val row = WorkoutSessions
            .select(pushUpSum, creditsSum, qualityAvg, sessionCount)
            .where {
                (WorkoutSessions.userId    eq friendId) and
                (WorkoutSessions.startedAt greaterEq fromInstant) and
                (WorkoutSessions.startedAt less toInstant) and
                WorkoutSessions.endedAt.isNotNull()
            }
            .firstOrNull()

        val pushups  = row?.get(pushUpSum)?.toInt()  ?: 0
        val credits  = row?.get(creditsSum)?.toLong() ?: 0L
        val sessions = row?.get(sessionCount)?.toInt() ?: 0
        val quality  = row?.get(qualityAvg)?.toDouble()

        // ------------------------------------------------------------------
        // 4. Compute the friend's current workout streak
        //
        // PostgreSQL requires that ORDER BY expressions appear in the SELECT
        // list when using SELECT DISTINCT. Since startedAtDay is a
        // CustomFunction (DATE_TRUNC), Exposed generates two separate
        // parameter bindings -- one for SELECT, one for ORDER BY -- which
        // PostgreSQL rejects as "not in select list".
        //
        // Solution: fetch all rows without DISTINCT/ORDER BY, then
        // deduplicate and sort in Kotlin. The result set is bounded by the
        // total number of completed sessions for this user, which is small
        // enough that in-memory deduplication is not a concern.
        // ------------------------------------------------------------------
        val workoutDays: List<LocalDate> = WorkoutSessions
            .select(WorkoutSessions.startedAtDay)
            .where {
                (WorkoutSessions.userId eq friendId) and
                WorkoutSessions.endedAt.isNotNull()
            }
            .map { it[WorkoutSessions.startedAtDay].atZone(ZoneOffset.UTC).toLocalDate() }
            .distinct()
            .sortedDescending()

        val currentStreak = calculateCurrentStreak(workoutDays, today)

        // ------------------------------------------------------------------
        // 5. Look up the friend's current XP level
        //
        // The user_levels table stores total_xp; the level number is derived
        // using the same formula as LevelCalculator in the shared KMP module:
        //   xpRequiredForLevel(n) = floor(100 * n^1.5)
        // If no row exists yet the friend is treated as level 1.
        // ------------------------------------------------------------------
        val totalXp = UserLevels
            .select(UserLevels.totalXp)
            .where { UserLevels.userId eq friendId }
            .firstOrNull()
            ?.get(UserLevels.totalXp) ?: 0L

        val friendLevel = levelFromTotalXp(totalXp)

        FriendActivityStatsResult.Success(
            FriendActivityStatsDTO(
                friendId           = friendId.toString(),
                period             = period.name,
                dateRange          = DateRangeDTO(
                    from = from.format(ISO_DATE),
                    to   = to.format(ISO_DATE),
                ),
                pushupCount        = pushups,
                totalSessions      = sessions,
                totalEarnedSeconds = credits,
                averageQuality     = quality,
                currentStreak      = currentStreak,
                friendLevel        = friendLevel,
            ),
        )
    }

    // -----------------------------------------------------------------------
    // Pure helpers -- no DB access, fully unit-testable
    // -----------------------------------------------------------------------

    /**
     * Current streak: consecutive days backwards from [today].
     * Streak is alive when the most recent workout was today or yesterday.
     * [workoutDaysSortedDesc] must be sorted descending (most recent first).
     *
     * Mirrors [StatsService.calculateCurrentStreak] so the logic is consistent.
     */
    internal fun calculateCurrentStreak(
        workoutDaysSortedDesc: List<LocalDate>,
        today: LocalDate,
    ): Int {
        if (workoutDaysSortedDesc.isEmpty()) return 0
        val mostRecent = workoutDaysSortedDesc.first()
        if (mostRecent.isBefore(today.minusDays(1))) return 0

        var streak = 0
        var expected = if (mostRecent == today) today else today.minusDays(1)
        for (day in workoutDaysSortedDesc) {
            when {
                day == expected -> { streak++; expected = expected.minusDays(1) }
                day.isBefore(expected) -> break
            }
        }
        return streak
    }

    /**
     * Returns the inclusive [from, to] date range for the given [period]
     * relative to [today].
     *
     * - day   -> [today, today]
     * - week  -> [Monday of the current ISO week, Sunday of the current ISO week]
     * - month -> [first day of the current month, last day of the current month]
     */
    internal fun dateRangeFor(period: StatsPeriod, today: LocalDate): Pair<LocalDate, LocalDate> =
        when (period) {
            StatsPeriod.day -> today to today

            StatsPeriod.week -> {
                val monday = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
                val sunday = monday.plusDays(6)
                monday to sunday
            }

            StatsPeriod.month -> {
                val first = today.withDayOfMonth(1)
                val last  = today.with(TemporalAdjusters.lastDayOfMonth())
                first to last
            }
        }

    // -----------------------------------------------------------------------
    // Pure helpers -- no DB access, fully unit-testable
    // -----------------------------------------------------------------------

    /**
     * Derives the level number from [totalXp] using the same formula as
     * `LevelCalculator` in the shared KMP module:
     *
     *   xpRequiredForLevel(n) = floor(100 * n^1.5)
     *
     * Iterates upward from level 1 until the accumulated threshold exceeds
     * [totalXp]. Returns the last level whose threshold was not exceeded.
     */
    internal fun levelFromTotalXp(totalXp: Long): Int {
        var level = 1
        var accumulated = 0L
        while (true) {
            val needed = floor(100.0 * level.toDouble().pow(1.5)).toLong()
            if (accumulated + needed > totalXp) break
            accumulated += needed
            level++
        }
        return level
    }

    // -----------------------------------------------------------------------
    // Companion / constants
    // -----------------------------------------------------------------------

    companion object {
        private val ISO_DATE: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE
    }
}
