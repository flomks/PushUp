package com.pushup.service

import com.pushup.dto.DailyStatsDTO
import com.pushup.dto.MonthlyStatsDTO
import com.pushup.dto.StreakDTO
import com.pushup.dto.TotalStatsDTO
import com.pushup.dto.WeeklyStatsDTO
import org.jetbrains.exposed.sql.CustomFunction
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
import org.jetbrains.exposed.sql.javatime.JavaInstantColumnType
import org.jetbrains.exposed.sql.javatime.timestamp
import org.jetbrains.exposed.sql.max
import org.jetbrains.exposed.sql.min
import org.jetbrains.exposed.sql.stringParam
import org.jetbrains.exposed.sql.sum
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import java.util.UUID

// ---------------------------------------------------------------------------
// Exposed table definition (mirrors public.workout_sessions in Supabase)
// ---------------------------------------------------------------------------

object WorkoutSessions : Table("workout_sessions") {
    val id = uuid("id")
    val userId = uuid("user_id").references(com.pushup.plugins.Users.id)
    val startedAt = timestamp("started_at")
    val endedAt = timestamp("ended_at").nullable()
    val pushUpCount = integer("push_up_count")
    val earnedTimeCredits = integer("earned_time_credits")
    val quality = float("quality")

    override val primaryKey = PrimaryKey(id)

    /**
     * PostgreSQL DATE_TRUNC('day', started_at) expression.
     * Truncates the timestamp to midnight UTC of the same calendar day.
     * Used as GROUP BY key for per-day aggregation.
     */
    val startedAtDay = CustomFunction<Instant>(
        functionName = "DATE_TRUNC",
        columnType = JavaInstantColumnType(),
        stringParam("day"),
        startedAt,
    )
}

// ---------------------------------------------------------------------------
// Reusable aggregate expression instances
// ---------------------------------------------------------------------------

/**
 * Aggregate expressions are created once and reused across all queries and
 * result-row lookups. Exposed resolves ResultRow[expr] by structural equality,
 * but sharing the same instances eliminates any ambiguity and is the
 * documented best practice.
 */
private val pushUpSum = WorkoutSessions.pushUpCount.sum()
private val creditsSum = WorkoutSessions.earnedTimeCredits.sum()
private val qualityAvg = WorkoutSessions.quality.avg()
private val sessionCount = WorkoutSessions.id.count()
private val bestSessionExpr = WorkoutSessions.pushUpCount.max()
private val firstWorkoutExpr = WorkoutSessions.startedAt.min()

// ---------------------------------------------------------------------------
// StatsService
// ---------------------------------------------------------------------------

/**
 * Executes aggregated statistics queries against PostgreSQL via Exposed 0.61.0 DSL.
 *
 * Design:
 * - Each public method opens exactly ONE transaction with ONE SQL query
 *   (weekly/monthly build their breakdowns from a single GROUP BY result).
 * - Aggregation uses DATE_TRUNC('day', started_at) so multiple sessions on
 *   the same calendar day are correctly summed.
 * - Monthly totals are computed from the month's own date range, not from
 *   the weekly breakdowns (which may include days outside the month).
 * - Streak calculation is pure (no DB) and fully unit-testable.
 */
class StatsService {

    // -----------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------

    suspend fun getDailyStats(userId: UUID, date: LocalDate): DailyStatsDTO = newSuspendedTransaction {
        val dayStart = date.atStartOfDay().toInstant(ZoneOffset.UTC)
        val dayEnd = date.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)
        val byDay = fetchDailyAggregates(userId, dayStart, dayEnd)
        byDay[date] ?: emptyDailyStats(date)
    }

    suspend fun getWeeklyStats(userId: UUID, weekStart: LocalDate): WeeklyStatsDTO = newSuspendedTransaction {
        val monday = weekStart.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val sunday = monday.plusDays(6)
        val from = monday.atStartOfDay().toInstant(ZoneOffset.UTC)
        val to = sunday.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)

        val byDay = fetchDailyAggregates(userId, from, to)
        buildWeeklyDTO(monday, byDay)
    }

    suspend fun getMonthlyStats(userId: UUID, month: Int, year: Int): MonthlyStatsDTO = newSuspendedTransaction {
        val firstDay = LocalDate.of(year, month, 1)
        val lastDay = firstDay.with(TemporalAdjusters.lastDayOfMonth())

        // Fetch the full range covering all overlapping ISO weeks
        val firstMonday = firstDay.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val lastSunday = lastDay.with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY))
        val from = firstMonday.atStartOfDay().toInstant(ZoneOffset.UTC)
        val to = lastSunday.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)

        val byDay = fetchDailyAggregates(userId, from, to)

        // Build weekly breakdown
        val weekMondays = mutableListOf<LocalDate>()
        var cursor = firstMonday
        while (!cursor.isAfter(lastDay)) { weekMondays.add(cursor); cursor = cursor.plusWeeks(1) }

        val weeklyBreakdown = weekMondays.map { monday -> buildWeeklyDTO(monday, byDay) }

        // Monthly totals are computed ONLY from days within the month (not from
        // the weekly breakdowns which include days outside the month boundary).
        val monthDays = byDay.filterKeys { it in firstDay..lastDay }

        MonthlyStatsDTO(
            month = month,
            year = year,
            totalPushUps = monthDays.values.sumOf { it.totalPushUps },
            totalSessions = monthDays.values.sumOf { it.totalSessions },
            totalEarnedSeconds = monthDays.values.sumOf { it.totalEarnedSeconds },
            averageQuality = monthDays.values.mapNotNull { it.averageQuality }
                .takeIf { it.isNotEmpty() }?.average(),
            weeklyBreakdown = weeklyBreakdown,
        )
    }

    suspend fun getTotalStats(userId: UUID): TotalStatsDTO = newSuspendedTransaction {
        val row = WorkoutSessions
            .select(pushUpSum, creditsSum, qualityAvg, sessionCount, bestSessionExpr, firstWorkoutExpr)
            .where {
                (WorkoutSessions.userId eq userId) and
                    WorkoutSessions.endedAt.isNotNull()
            }
            .firstOrNull()

        if (row == null) return@newSuspendedTransaction emptyTotalStats()

        val sessions = row[sessionCount].toInt()
        val pushUps = row[pushUpSum] ?: 0
        val firstInstant: Instant? = row[firstWorkoutExpr]

        TotalStatsDTO(
            totalPushUps = pushUps,
            totalSessions = sessions,
            totalEarnedSeconds = (row[creditsSum] ?: 0).toLong(),
            averageQuality = row[qualityAvg]?.toDouble(),
            averagePushUpsPerSession = if (sessions > 0) pushUps.toDouble() / sessions else null,
            bestSessionPushUps = row[bestSessionExpr],
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
     * Uses DISTINCT DATE_TRUNC in SQL so deduplication happens in the database,
     * not in JVM memory.
     *
     * @param today Injectable for deterministic unit tests (defaults to UTC today).
     */
    suspend fun getStreak(userId: UUID, today: LocalDate = LocalDate.now(ZoneOffset.UTC)): StreakDTO = newSuspendedTransaction {
        // SELECT DISTINCT DATE_TRUNC('day', started_at) ... ORDER BY 1 ASC
        val workoutDays: List<LocalDate> = WorkoutSessions
            .select(WorkoutSessions.startedAtDay)
            .where {
                (WorkoutSessions.userId eq userId) and
                    WorkoutSessions.endedAt.isNotNull()
            }
            .withDistinct()
            .orderBy(WorkoutSessions.startedAtDay to SortOrder.ASC)
            .map { row: ResultRow ->
                row[WorkoutSessions.startedAtDay].atZone(ZoneOffset.UTC).toLocalDate()
            }

        if (workoutDays.isEmpty()) {
            return@newSuspendedTransaction StreakDTO(currentStreak = 0, longestStreak = 0, lastWorkoutDate = null)
        }

        val descending = workoutDays.asReversed() // already ASC, reverse is O(1)

        StreakDTO(
            currentStreak = calculateCurrentStreak(descending, today),
            longestStreak = calculateLongestStreak(workoutDays),
            lastWorkoutDate = descending.first().format(ISO_DATE),
        )
    }

    // -----------------------------------------------------------------------
    // Private DB helpers
    // -----------------------------------------------------------------------

    /**
     * Fetches per-day aggregated stats for [userId] in the half-open range [from, to).
     *
     * Returns a map of LocalDate to DailyStatsDTO. Days with no completed
     * sessions are absent from the map -- callers fill in zeros themselves.
     *
     * Uses DATE_TRUNC('day', started_at) as the GROUP BY key so multiple
     * sessions on the same calendar day are correctly aggregated.
     */
    private fun fetchDailyAggregates(userId: UUID, from: Instant, to: Instant): Map<LocalDate, DailyStatsDTO> {
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
                date to DailyStatsDTO(
                    date = date.format(ISO_DATE),
                    totalPushUps = row[pushUpSum] ?: 0,
                    totalSessions = row[sessionCount].toInt(),
                    totalEarnedSeconds = (row[creditsSum] ?: 0).toLong(),
                    averageQuality = row[qualityAvg]?.toDouble(),
                )
            }
    }

    // -----------------------------------------------------------------------
    // Private DTO builders
    // -----------------------------------------------------------------------

    private fun buildWeeklyDTO(monday: LocalDate, byDay: Map<LocalDate, DailyStatsDTO>): WeeklyStatsDTO {
        val sunday = monday.plusDays(6)
        val dailyBreakdown = (0L..6L).map { offset ->
            val day = monday.plusDays(offset)
            byDay[day] ?: emptyDailyStats(day)
        }
        return WeeklyStatsDTO(
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

        private fun emptyDailyStats(date: LocalDate) = DailyStatsDTO(
            date = date.format(ISO_DATE),
            totalPushUps = 0,
            totalSessions = 0,
            totalEarnedSeconds = 0L,
            averageQuality = null,
        )

        private fun emptyTotalStats() = TotalStatsDTO(
            totalPushUps = 0,
            totalSessions = 0,
            totalEarnedSeconds = 0L,
            averageQuality = null,
            averagePushUpsPerSession = null,
            bestSessionPushUps = null,
            firstWorkoutDate = null,
        )
    }
}
