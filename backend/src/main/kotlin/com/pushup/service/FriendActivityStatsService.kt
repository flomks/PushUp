package com.pushup.service

import com.pushup.dto.DateRangeDTO
import com.pushup.dto.FriendActivityDayDTO
import com.pushup.dto.FriendActivityStatsDTO
import com.pushup.dto.FriendExerciseLevelDTO
import com.pushup.dto.FriendLevelDetailsDTO
import com.pushup.dto.FriendMonthlyActivityDTO
import com.pushup.dto.StatsPeriod
import com.pushup.plugins.ExerciseLevels
import com.pushup.plugins.FriendshipStatus
import com.pushup.plugins.Friendships
import com.pushup.plugins.JoggingSessions
import com.pushup.plugins.UserLevels
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.greaterEq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.isNotNull
import org.jetbrains.exposed.sql.SqlExpressionBuilder.less
import org.jetbrains.exposed.sql.and
import org.jetbrains.exposed.sql.avg
import org.jetbrains.exposed.sql.count
import org.jetbrains.exposed.sql.select
import org.jetbrains.exposed.sql.or
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.sum
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import java.time.OffsetDateTime
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

sealed class FriendMonthlyActivityResult {
    data class Success(val summary: FriendMonthlyActivityDTO) : FriendMonthlyActivityResult()
    object NotFriends : FriendMonthlyActivityResult()
    object FriendNotFound : FriendMonthlyActivityResult()
}

sealed class FriendLevelDetailsResult {
    data class Success(val details: FriendLevelDetailsDTO) : FriendLevelDetailsResult()
    object NotFriends : FriendLevelDetailsResult()
    object FriendNotFound : FriendLevelDetailsResult()
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
        when (friendGuard(callerId, friendId)) {
            FriendGuardResult.NotFriends -> return@newSuspendedTransaction FriendActivityStatsResult.NotFriends
            FriendGuardResult.FriendNotFound -> return@newSuspendedTransaction FriendActivityStatsResult.FriendNotFound
            FriendGuardResult.Ok -> Unit
        }

        // ------------------------------------------------------------------
        // 2. Compute the date range for the requested period
        // ------------------------------------------------------------------
        val (from, to) = dateRangeFor(period, today)

        val fromInstant: Instant = from.atStartOfDay().toInstant(ZoneOffset.UTC)
        // toInstant is exclusive: start of the day AFTER the last day of the period
        val toInstant: Instant   = to.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)

        // ------------------------------------------------------------------
        // 3. Aggregate stats for the friend in the date range
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

        val pushups        = row?.get(pushUpSum)?.toInt() ?: 0
        val workoutCredits = row?.get(creditsSum)?.toLong() ?: 0L
        val workoutSessions = row?.get(sessionCount)?.toInt() ?: 0
        val quality        = row?.get(qualityAvg)?.toDouble()

        val joggingCount = JoggingSessions.id.count()
        val joggingCreditsSum = JoggingSessions.earnedTimeCredits.sum()
        val distanceSum = JoggingSessions.distanceMeters.sum()

        val joggingRow = JoggingSessions
            .select(joggingCount, joggingCreditsSum, distanceSum)
            .where {
                (JoggingSessions.userId eq friendId) and
                    (JoggingSessions.startedAt greaterEq OffsetDateTime.ofInstant(fromInstant, ZoneOffset.UTC)) and
                    (JoggingSessions.startedAt less OffsetDateTime.ofInstant(toInstant, ZoneOffset.UTC)) and
                    JoggingSessions.endedAt.isNotNull()
            }
            .firstOrNull()

        val joggingSessions = joggingRow?.get(joggingCount)?.toInt() ?: 0
        val joggingCredits = joggingRow?.get(joggingCreditsSum)?.toLong() ?: 0L
        val joggingDistanceMeters = joggingRow?.get(distanceSum)?.toDouble() ?: 0.0

        val activityPoints = calculateWorkoutActivityPoints(pushups, quality) +
            calculateJoggingActivityPoints(joggingDistanceMeters)
        val totalSessions = workoutSessions + joggingSessions
        val totalEarnedSeconds = workoutCredits + joggingCredits

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

        // Include jogging sessions for unified streak calculation
        val joggingDays: List<LocalDate> = com.pushup.plugins.JoggingSessions
            .select(com.pushup.plugins.JoggingSessions.startedAtDay)
            .where {
                (com.pushup.plugins.JoggingSessions.userId eq friendId) and
                com.pushup.plugins.JoggingSessions.endedAt.isNotNull()
            }
            .map { it[com.pushup.plugins.JoggingSessions.startedAtDay].atZone(ZoneOffset.UTC).toLocalDate() }

        val allActivityDays = (workoutDays + joggingDays)
            .distinct()
            .sortedDescending()

        val currentStreak = calculateCurrentStreak(allActivityDays, today)

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
                activityPoints     = activityPoints,
                pushupCount        = pushups,
                totalSessions      = totalSessions,
                totalEarnedSeconds = totalEarnedSeconds,
                averageQuality     = quality,
                currentStreak      = currentStreak,
                friendLevel        = friendLevel,
            ),
        )
    }

    open suspend fun getMonthlyActivity(
        callerId: UUID,
        friendId: UUID,
        month: Int,
        year: Int,
    ): FriendMonthlyActivityResult = newSuspendedTransaction {
        when (friendGuard(callerId, friendId)) {
            FriendGuardResult.NotFriends -> return@newSuspendedTransaction FriendMonthlyActivityResult.NotFriends
            FriendGuardResult.FriendNotFound -> return@newSuspendedTransaction FriendMonthlyActivityResult.FriendNotFound
            FriendGuardResult.Ok -> Unit
        }

        val firstDay = LocalDate.of(year, month, 1)
        val lastDay = firstDay.with(TemporalAdjusters.lastDayOfMonth())
        val from = firstDay.atStartOfDay().toInstant(ZoneOffset.UTC)
        val to = lastDay.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)

        val workoutByDay = fetchWorkoutDailyAggregates(friendId, from, to)
        val joggingByDay = fetchJoggingDailyAggregates(friendId, from, to)

        val allDates = generateSequence(firstDay) { it.plusDays(1) }
            .takeWhile { !it.isAfter(lastDay) }
            .toList()

        val days = allDates.map { date ->
            val workout = workoutByDay[date]
            val jogging = joggingByDay[date]
            val pushupCount = workout?.pushupCount ?: 0
            val averageQuality = workout?.averageQuality
            val joggingDistanceMeters = jogging?.distanceMeters ?: 0.0

            FriendActivityDayDTO(
                date = date.format(ISO_DATE),
                activityPoints = calculateWorkoutActivityPoints(pushupCount, averageQuality) +
                    calculateJoggingActivityPoints(joggingDistanceMeters),
                totalSessions = (workout?.totalSessions ?: 0) + (jogging?.totalSessions ?: 0),
                totalEarnedSeconds = (workout?.totalEarnedSeconds ?: 0L) + (jogging?.totalEarnedSeconds ?: 0L),
            )
        }

        FriendMonthlyActivityResult.Success(
            FriendMonthlyActivityDTO(
                friendId = friendId.toString(),
                month = month,
                year = year,
                days = days,
                activeDays = days.count { it.totalSessions > 0 },
                totalSessions = days.sumOf { it.totalSessions },
                totalActivityPoints = days.sumOf { it.activityPoints },
                totalEarnedSeconds = days.sumOf { it.totalEarnedSeconds },
            )
        )
    }

    open suspend fun getLevelDetails(
        callerId: UUID,
        friendId: UUID,
    ): FriendLevelDetailsResult = newSuspendedTransaction {
        when (friendGuard(callerId, friendId)) {
            FriendGuardResult.NotFriends -> return@newSuspendedTransaction FriendLevelDetailsResult.NotFriends
            FriendGuardResult.FriendNotFound -> return@newSuspendedTransaction FriendLevelDetailsResult.FriendNotFound
            FriendGuardResult.Ok -> Unit
        }

        val totalXp = UserLevels
            .select(UserLevels.totalXp)
            .where { UserLevels.userId eq friendId }
            .firstOrNull()
            ?.get(UserLevels.totalXp) ?: 0L

        val levelDetails = buildLevelDetails(totalXp)
        val exerciseLevels = ExerciseLevels
            .selectAll()
            .where { ExerciseLevels.userId eq friendId }
            .map { row ->
                val exerciseXp = row[ExerciseLevels.totalXp]
                val details = buildLevelDetails(exerciseXp)
                FriendExerciseLevelDTO(
                    exerciseTypeId = row[ExerciseLevels.exerciseType],
                    level = details.level,
                    totalXp = exerciseXp,
                    xpIntoLevel = details.xpIntoLevel,
                    xpRequiredForNextLevel = details.xpRequiredForNextLevel,
                    levelProgress = details.levelProgress,
                )
            }
            .sortedBy { it.exerciseTypeId }

        FriendLevelDetailsResult.Success(
            FriendLevelDetailsDTO(
                friendId = friendId.toString(),
                level = levelDetails.level,
                totalXp = totalXp,
                xpIntoLevel = levelDetails.xpIntoLevel,
                xpRequiredForNextLevel = levelDetails.xpRequiredForNextLevel,
                levelProgress = levelDetails.levelProgress,
                exerciseLevels = exerciseLevels,
            )
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

    private fun buildLevelDetails(totalXp: Long): FriendLevelProgress {
        var level = 1
        var consumedXp = 0L
        while (true) {
            val needed = xpRequiredForLevel(level)
            if (consumedXp + needed > totalXp) {
                val xpIntoLevel = totalXp - consumedXp
                return FriendLevelProgress(
                    level = level,
                    xpIntoLevel = xpIntoLevel,
                    xpRequiredForNextLevel = needed,
                    levelProgress = if (needed > 0) xpIntoLevel.toDouble() / needed.toDouble() else 0.0,
                )
            }
            consumedXp += needed
            level++
        }
    }

    private fun xpRequiredForLevel(level: Int): Long =
        floor(100.0 * level.toDouble().pow(1.5)).toLong()

    private fun calculateWorkoutActivityPoints(pushups: Int, quality: Double?): Int {
        val multiplier = when {
            quality == null -> 1.0
            quality > 0.8 -> 1.5
            quality >= 0.5 -> 1.0
            else -> 0.7
        }
        return (pushups * 10.0 * multiplier).toInt()
    }

    private fun calculateJoggingActivityPoints(distanceMeters: Double): Int {
        val distanceUnits = (distanceMeters / 100.0).toInt()
        return distanceUnits * 10
    }

    private fun friendGuard(callerId: UUID, friendId: UUID): FriendGuardResult {
        val friendExists = UserLevels
            .select(UserLevels.userId)
            .where { UserLevels.userId eq friendId }
            .limit(1)
            .count() > 0 || WorkoutSessions
            .select(WorkoutSessions.userId)
            .where { WorkoutSessions.userId eq friendId }
            .limit(1)
            .count() > 0 || JoggingSessions
            .select(JoggingSessions.userId)
            .where { JoggingSessions.userId eq friendId }
            .limit(1)
            .count() > 0 || Friendships
            .select(Friendships.requesterId)
            .where { (Friendships.requesterId eq friendId) or (Friendships.receiverId eq friendId) }
            .limit(1)
            .count() > 0

        if (!friendExists) return FriendGuardResult.FriendNotFound

        val friendshipExists = Friendships.selectAll()
            .where {
                (Friendships.status eq FriendshipStatus.ACCEPTED) and (
                    ((Friendships.requesterId eq callerId) and (Friendships.receiverId eq friendId)) or
                        ((Friendships.requesterId eq friendId) and (Friendships.receiverId eq callerId))
                    )
            }
            .count() > 0

        return if (friendshipExists) FriendGuardResult.Ok else FriendGuardResult.NotFriends
    }

    private fun fetchWorkoutDailyAggregates(
        userId: UUID,
        from: Instant,
        to: Instant,
    ): Map<LocalDate, WorkoutDailyAggregate> {
        val pushUpSum = WorkoutSessions.pushUpCount.sum()
        val creditsSum = WorkoutSessions.earnedTimeCredits.sum()
        val qualityAvg = WorkoutSessions.quality.avg()
        val sessionCount = WorkoutSessions.id.count()

        return WorkoutSessions
            .select(WorkoutSessions.startedAtDay, pushUpSum, creditsSum, qualityAvg, sessionCount)
            .where {
                (WorkoutSessions.userId eq userId) and
                    (WorkoutSessions.startedAt greaterEq from) and
                    (WorkoutSessions.startedAt less to) and
                    WorkoutSessions.endedAt.isNotNull()
            }
            .groupBy(WorkoutSessions.startedAtDay)
            .associate { row ->
                val date = row[WorkoutSessions.startedAtDay].atZone(ZoneOffset.UTC).toLocalDate()
                date to WorkoutDailyAggregate(
                    pushupCount = row[pushUpSum]?.toInt() ?: 0,
                    totalSessions = row[sessionCount].toInt(),
                    totalEarnedSeconds = (row[creditsSum] ?: 0).toLong(),
                    averageQuality = row[qualityAvg]?.toDouble(),
                )
            }
    }

    private fun fetchJoggingDailyAggregates(
        userId: UUID,
        from: Instant,
        to: Instant,
    ): Map<LocalDate, JoggingDailyAggregate> {
        val sessionCount = JoggingSessions.id.count()
        val creditsSum = JoggingSessions.earnedTimeCredits.sum()
        val distanceSum = JoggingSessions.distanceMeters.sum()
        val fromOffset = OffsetDateTime.ofInstant(from, ZoneOffset.UTC)
        val toOffset = OffsetDateTime.ofInstant(to, ZoneOffset.UTC)

        return JoggingSessions
            .select(JoggingSessions.startedAtDay, sessionCount, creditsSum, distanceSum)
            .where {
                (JoggingSessions.userId eq userId) and
                    (JoggingSessions.startedAt greaterEq fromOffset) and
                    (JoggingSessions.startedAt less toOffset) and
                    JoggingSessions.endedAt.isNotNull()
            }
            .groupBy(JoggingSessions.startedAtDay)
            .associate { row ->
                val date = row[JoggingSessions.startedAtDay].atZone(ZoneOffset.UTC).toLocalDate()
                date to JoggingDailyAggregate(
                    totalSessions = row[sessionCount].toInt(),
                    totalEarnedSeconds = (row[creditsSum] ?: 0).toLong(),
                    distanceMeters = row[distanceSum]?.toDouble() ?: 0.0,
                )
            }
    }

    // -----------------------------------------------------------------------
    // Companion / constants
    // -----------------------------------------------------------------------

    companion object {
        private val ISO_DATE: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE
    }
}

private enum class FriendGuardResult {
    Ok,
    NotFriends,
    FriendNotFound,
}

private data class WorkoutDailyAggregate(
    val pushupCount: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageQuality: Double?,
)

private data class JoggingDailyAggregate(
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val distanceMeters: Double,
)

private data class FriendLevelProgress(
    val level: Int,
    val xpIntoLevel: Long,
    val xpRequiredForNextLevel: Long,
    val levelProgress: Double,
)
