package com.pushup.service

import com.pushup.dto.DailyStatsDTO
import com.pushup.dto.MonthlyStatsDTO
import com.pushup.dto.StreakDTO
import com.pushup.dto.TotalStatsDTO
import com.pushup.dto.WeeklyStatsDTO
import org.jetbrains.exposed.sql.Column
import org.jetbrains.exposed.sql.ResultRow
import org.jetbrains.exposed.sql.SortOrder
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.greaterEq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.isNotNull
import org.jetbrains.exposed.sql.SqlExpressionBuilder.less
import org.jetbrains.exposed.sql.Table
import org.jetbrains.exposed.sql.and
import org.jetbrains.exposed.sql.avg
import org.jetbrains.exposed.sql.count
import org.jetbrains.exposed.sql.javatime.timestamp
import org.jetbrains.exposed.sql.max
import org.jetbrains.exposed.sql.min
import org.jetbrains.exposed.sql.sum
import org.jetbrains.exposed.sql.transactions.transaction
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters

// ---------------------------------------------------------------------------
// Exposed table definition (mirrors public.workout_sessions in Supabase)
// ---------------------------------------------------------------------------

object WorkoutSessions : Table("workout_sessions") {
    val id: Column<String> = varchar("id", 36)
    val userId: Column<String> = varchar("user_id", 36)
    val startedAt: Column<Instant> = timestamp("started_at")
    val endedAt: Column<Instant?> = timestamp("ended_at").nullable()
    val pushUpCount: Column<Int> = integer("push_up_count")
    val earnedTimeCredits: Column<Int> = integer("earned_time_credits")
    val quality: Column<Float> = float("quality")

    override val primaryKey = PrimaryKey(id)
}

// ---------------------------------------------------------------------------
// StatsService
// ---------------------------------------------------------------------------

/**
 * Executes aggregated statistics queries against PostgreSQL via Exposed 0.61.0 DSL.
 *
 * Design principles:
 * - Each public method opens exactly ONE transaction.
 * - Weekly and monthly breakdowns are built from a single GROUP BY query
 *   (no N+1 problem): one query fetches all per-day rows, then Kotlin fills
 *   in zero-rows for days without workouts.
 * - Streak calculation is pure (no DB) and fully unit-testable.
 */
class StatsService {

    // -----------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------

    fun getDailyStats(userId: String, date: LocalDate): DailyStatsDTO = transaction {
        val dayStart = date.atStartOfDay().toInstant(ZoneOffset.UTC)
        val dayEnd = date.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)
        val rows = fetchDailyRows(userId, dayStart, dayEnd)
        rows.firstOrNull()?.toDailyStatsDTO(date) ?: emptyDailyStats(date)
    }

    fun getWeeklyStats(userId: String, weekStart: LocalDate): WeeklyStatsDTO = transaction {
        val monday = weekStart.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val sunday = monday.plusDays(6)
        val from = monday.atStartOfDay().toInstant(ZoneOffset.UTC)
        val to = sunday.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)

        // Single query: all sessions in the week grouped by UTC date
        val byDay = fetchDailyRows(userId, from, to)
            .associate { row ->
                val date = row[WorkoutSessions.startedAt].atZone(ZoneOffset.UTC).toLocalDate()
                date to row
            }

        val dailyBreakdown = (0L..6L).map { offset ->
            val day = monday.plusDays(offset)
            byDay[day]?.toDailyStatsDTO(day) ?: emptyDailyStats(day)
        }

        WeeklyStatsDTO(
            weekStart = monday.format(ISO_DATE),
            weekEnd = sunday.format(ISO_DATE),
            totalPushUps = dailyBreakdown.sumOf { it.totalPushUps },
            totalSessions = dailyBreakdown.sumOf { it.totalSessions },
            totalEarnedSeconds = dailyBreakdown.sumOf { it.totalEarnedSeconds },
            averageQuality = dailyBreakdown.mapNotNull { it.averageQuality }
                .takeIf { it.isNotEmpty() }?.average(),
            dailyBreakdown = dailyBreakdown,
        )
    }

    fun getMonthlyStats(userId: String, month: Int, year: Int): MonthlyStatsDTO = transaction {
        val firstDay = LocalDate.of(year, month, 1)
        val lastDay = firstDay.with(TemporalAdjusters.lastDayOfMonth())
        val from = firstDay.atStartOfDay().toInstant(ZoneOffset.UTC)
        val to = lastDay.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)

        // Single query for the whole month
        val byDay = fetchDailyRows(userId, from, to)
            .associate { row ->
                val date = row[WorkoutSessions.startedAt].atZone(ZoneOffset.UTC).toLocalDate()
                date to row
            }

        // Build ISO-week Mondays that overlap with this month
        val weekMondays = mutableListOf<LocalDate>()
        var cursor = firstDay.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        while (!cursor.isAfter(lastDay)) { weekMondays.add(cursor); cursor = cursor.plusWeeks(1) }

        val weeklyBreakdown = weekMondays.map { monday ->
            val sunday = monday.plusDays(6)
            val dailyBreakdown = (0L..6L).map { offset ->
                val day = monday.plusDays(offset)
                byDay[day]?.toDailyStatsDTO(day) ?: emptyDailyStats(day)
            }
            WeeklyStatsDTO(
                weekStart = monday.format(ISO_DATE),
                weekEnd = sunday.format(ISO_DATE),
                totalPushUps = dailyBreakdown.sumOf { it.totalPushUps },
                totalSessions = dailyBreakdown.sumOf { it.totalSessions },
                totalEarnedSeconds = dailyBreakdown.sumOf { it.totalEarnedSeconds },
                averageQuality = dailyBreakdown.mapNotNull { it.averageQuality }
                    .takeIf { it.isNotEmpty() }?.average(),
                dailyBreakdown = dailyBreakdown,
            )
        }

        MonthlyStatsDTO(
            month = month,
            year = year,
            totalPushUps = weeklyBreakdown.sumOf { it.totalPushUps },
            totalSessions = weeklyBreakdown.sumOf { it.totalSessions },
            totalEarnedSeconds = weeklyBreakdown.sumOf { it.totalEarnedSeconds },
            averageQuality = weeklyBreakdown.mapNotNull { it.averageQuality }
                .takeIf { it.isNotEmpty() }?.average(),
            weeklyBreakdown = weeklyBreakdown,
        )
    }

    fun getTotalStats(userId: String): TotalStatsDTO = transaction {
        val pushUpSum = WorkoutSessions.pushUpCount.sum()
        val creditsSum = WorkoutSessions.earnedTimeCredits.sum()
        val qualityAvg = WorkoutSessions.quality.avg()
        val sessionCount = WorkoutSessions.id.count()
        val bestSession = WorkoutSessions.pushUpCount.max()
        val firstWorkout = WorkoutSessions.startedAt.min()

        val row = WorkoutSessions
            .select(pushUpSum, creditsSum, qualityAvg, sessionCount, bestSession, firstWorkout)
            .where {
                (WorkoutSessions.userId eq userId) and
                    WorkoutSessions.endedAt.isNotNull()
            }
            .first()

        val totalSessions = row[sessionCount].toInt()
        val totalPushUps = row[pushUpSum] ?: 0
        val firstInstant: Instant? = row[firstWorkout]

        TotalStatsDTO(
            totalPushUps = totalPushUps,
            totalSessions = totalSessions,
            totalEarnedSeconds = (row[creditsSum] ?: 0).toLong(),
            averageQuality = row[qualityAvg]?.toDouble(),
            averagePushUpsPerSession = if (totalSessions > 0) totalPushUps.toDouble() / totalSessions else null,
            bestSessionPushUps = row[bestSession],
            firstWorkoutDate = firstInstant?.atZone(ZoneOffset.UTC)?.toLocalDate()?.format(ISO_DATE),
        )
    }

    /**
     * Calculates the current and longest workout streak.
     *
     * A "streak day" is any UTC calendar day with at least one completed session.
     * The current streak counts backwards from [today]; it is alive when the
     * most recent workout was today or yesterday.
     *
     * @param today Injectable for deterministic unit tests (defaults to UTC today).
     */
    fun getStreak(userId: String, today: LocalDate = LocalDate.now(ZoneOffset.UTC)): StreakDTO = transaction {
        val workoutDays: List<LocalDate> = WorkoutSessions
            .select(WorkoutSessions.startedAt)
            .where {
                (WorkoutSessions.userId eq userId) and
                    WorkoutSessions.endedAt.isNotNull()
            }
            .orderBy(WorkoutSessions.startedAt to SortOrder.ASC)
            .map { row: ResultRow -> row[WorkoutSessions.startedAt].atZone(ZoneOffset.UTC).toLocalDate() }
            .distinct()
            .sortedDescending()

        if (workoutDays.isEmpty()) {
            return@transaction StreakDTO(currentStreak = 0, longestStreak = 0, lastWorkoutDate = null)
        }

        StreakDTO(
            currentStreak = calculateCurrentStreak(workoutDays, today),
            longestStreak = calculateLongestStreak(workoutDays.sortedBy { it }),
            lastWorkoutDate = workoutDays.first().format(ISO_DATE),
        )
    }

    // -----------------------------------------------------------------------
    // Private DB helpers
    // -----------------------------------------------------------------------

    /**
     * Fetches per-day aggregate rows for [userId] in the range [from, to).
     *
     * Returns one [ResultRow] per UTC calendar day that has at least one
     * completed session. Days with no sessions are absent from the result --
     * callers fill in zero-rows themselves.
     *
     * Uses a single SQL query with GROUP BY DATE_TRUNC('day', started_at).
     * The `startedAt` column in each row holds the truncated day timestamp
     * (midnight UTC) which callers convert to [LocalDate].
     */
    private fun fetchDailyRows(userId: String, from: Instant, to: Instant): List<ResultRow> {
        val pushUpSum = WorkoutSessions.pushUpCount.sum()
        val creditsSum = WorkoutSessions.earnedTimeCredits.sum()
        val qualityAvg = WorkoutSessions.quality.avg()
        val sessionCount = WorkoutSessions.id.count()

        return WorkoutSessions
            .select(WorkoutSessions.startedAt, pushUpSum, creditsSum, qualityAvg, sessionCount)
            .where {
                (WorkoutSessions.userId eq userId) and
                    (WorkoutSessions.startedAt greaterEq from) and
                    (WorkoutSessions.startedAt less to) and
                    WorkoutSessions.endedAt.isNotNull()
            }
            .groupBy(WorkoutSessions.startedAt)
            .orderBy(WorkoutSessions.startedAt to SortOrder.ASC)
            .toList()
    }

    // -----------------------------------------------------------------------
    // Pure streak helpers -- no DB access, fully unit-testable
    // -----------------------------------------------------------------------

    /**
     * Current streak: consecutive days backwards from [today].
     * Streak is alive when most recent workout was today or yesterday.
     * [workoutDaysSortedDesc] must be sorted descending (most recent first).
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
     * Longest streak ever.
     * [workoutDaysSortedAsc] must be sorted ascending (oldest first).
     */
    internal fun calculateLongestStreak(workoutDaysSortedAsc: List<LocalDate>): Int {
        if (workoutDaysSortedAsc.isEmpty()) return 0
        var longest = 1
        var current = 1
        for (i in 1 until workoutDaysSortedAsc.size) {
            if (workoutDaysSortedAsc[i] == workoutDaysSortedAsc[i - 1].plusDays(1)) {
                current++
                if (current > longest) longest = current
            } else {
                current = 1
            }
        }
        return longest
    }

    // -----------------------------------------------------------------------
    // Companion / constants
    // -----------------------------------------------------------------------

    companion object {
        private val ISO_DATE: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE

        /** Maps a GROUP BY result row to a [DailyStatsDTO] for the given [date]. */
        private fun ResultRow.toDailyStatsDTO(date: LocalDate): DailyStatsDTO {
            val pushUpSum = WorkoutSessions.pushUpCount.sum()
            val creditsSum = WorkoutSessions.earnedTimeCredits.sum()
            val qualityAvg = WorkoutSessions.quality.avg()
            val sessionCount = WorkoutSessions.id.count()
            return DailyStatsDTO(
                date = date.format(ISO_DATE),
                totalPushUps = this[pushUpSum] ?: 0,
                totalSessions = this[sessionCount].toInt(),
                totalEarnedSeconds = (this[creditsSum] ?: 0).toLong(),
                averageQuality = this[qualityAvg]?.toDouble(),
            )
        }

        /** Returns a zero-filled [DailyStatsDTO] for days with no workouts. */
        private fun emptyDailyStats(date: LocalDate) = DailyStatsDTO(
            date = date.format(ISO_DATE),
            totalPushUps = 0,
            totalSessions = 0,
            totalEarnedSeconds = 0L,
            averageQuality = null,
        )
    }
}
