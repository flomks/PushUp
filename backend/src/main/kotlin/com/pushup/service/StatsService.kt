@file:Suppress("UNCHECKED_CAST")

package com.pushup.service

import com.pushup.dto.DailyStatsDTO
import com.pushup.dto.MonthlyStatsDTO
import com.pushup.dto.StreakDTO
import com.pushup.dto.TotalStatsDTO
import com.pushup.dto.WeeklyStatsDTO
import org.jetbrains.exposed.sql.Column
import org.jetbrains.exposed.sql.ResultRow
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.greaterEq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.isNotNull
import org.jetbrains.exposed.sql.SqlExpressionBuilder.less
import org.jetbrains.exposed.sql.SortOrder
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
 * Correct Exposed 0.61.0 query pattern:
 *   Table.select(col1, col2)          // ColumnSet.select() → Query (picks columns)
 *       .where { col eq value and … } // Query.where { SqlExpressionBuilder lambda }
 *       .first()
 *
 * Aggregate functions (sum, avg, count, min, max) are passed directly to
 * ColumnSet.select() which accepts vararg Expression<?>.
 * The @file:Suppress("UNCHECKED_CAST") covers the aggregate → Expression casts.
 */
class StatsService {

    // -----------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------

    fun getDailyStats(userId: String, date: LocalDate): DailyStatsDTO = transaction {
        queryDailyStats(userId, date)
    }

    fun getWeeklyStats(userId: String, weekStart: LocalDate): WeeklyStatsDTO = transaction {
        queryWeeklyStats(userId, weekStart)
    }

    fun getMonthlyStats(userId: String, month: Int, year: Int): MonthlyStatsDTO = transaction {
        val firstDay = LocalDate.of(year, month, 1)
        val lastDay = firstDay.with(TemporalAdjusters.lastDayOfMonth())
        val monthStart = firstDay.atStartOfDay().toInstant(ZoneOffset.UTC)
        val monthEnd = lastDay.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)

        val pushUpSum = WorkoutSessions.pushUpCount.sum()
        val creditsSum = WorkoutSessions.earnedTimeCredits.sum()
        val qualityAvg = WorkoutSessions.quality.avg()
        val sessionCount = WorkoutSessions.id.count()

        val row = WorkoutSessions
            .select(pushUpSum, creditsSum, qualityAvg, sessionCount)
            .where {
                (WorkoutSessions.userId eq userId) and
                    (WorkoutSessions.startedAt greaterEq monthStart) and
                    (WorkoutSessions.startedAt less monthEnd) and
                    WorkoutSessions.endedAt.isNotNull()
            }
            .first()

        val weekMondays = mutableListOf<LocalDate>()
        var cursor = firstDay.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        while (!cursor.isAfter(lastDay)) { weekMondays.add(cursor); cursor = cursor.plusWeeks(1) }

        MonthlyStatsDTO(
            month = month,
            year = year,
            totalPushUps = row[pushUpSum] ?: 0,
            totalSessions = row[sessionCount].toInt(),
            totalEarnedSeconds = (row[creditsSum] ?: 0).toLong(),
            averageQuality = row[qualityAvg]?.toDouble(),
            weeklyBreakdown = weekMondays.map { queryWeeklyStats(userId, it) },
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
        val firstDate = firstInstant?.atZone(ZoneOffset.UTC)?.toLocalDate()
            ?.format(DateTimeFormatter.ISO_LOCAL_DATE)

        TotalStatsDTO(
            totalPushUps = totalPushUps,
            totalSessions = totalSessions,
            totalEarnedSeconds = (row[creditsSum] ?: 0).toLong(),
            averageQuality = row[qualityAvg]?.toDouble(),
            averagePushUpsPerSession = if (totalSessions > 0) totalPushUps.toDouble() / totalSessions else null,
            bestSessionPushUps = row[bestSession],
            firstWorkoutDate = firstDate,
        )
    }

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
            lastWorkoutDate = workoutDays.first().format(DateTimeFormatter.ISO_LOCAL_DATE),
        )
    }

    // -----------------------------------------------------------------------
    // Private query helpers (must be called inside an existing transaction)
    // -----------------------------------------------------------------------

    private fun queryDailyStats(userId: String, date: LocalDate): DailyStatsDTO {
        val dayStart = date.atStartOfDay().toInstant(ZoneOffset.UTC)
        val dayEnd = date.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)

        val pushUpSum = WorkoutSessions.pushUpCount.sum()
        val creditsSum = WorkoutSessions.earnedTimeCredits.sum()
        val qualityAvg = WorkoutSessions.quality.avg()
        val sessionCount = WorkoutSessions.id.count()

        val row = WorkoutSessions
            .select(pushUpSum, creditsSum, qualityAvg, sessionCount)
            .where {
                (WorkoutSessions.userId eq userId) and
                    (WorkoutSessions.startedAt greaterEq dayStart) and
                    (WorkoutSessions.startedAt less dayEnd) and
                    WorkoutSessions.endedAt.isNotNull()
            }
            .first()

        return DailyStatsDTO(
            date = date.format(DateTimeFormatter.ISO_LOCAL_DATE),
            totalPushUps = row[pushUpSum] ?: 0,
            totalSessions = row[sessionCount].toInt(),
            totalEarnedSeconds = (row[creditsSum] ?: 0).toLong(),
            averageQuality = row[qualityAvg]?.toDouble(),
        )
    }

    private fun queryWeeklyStats(userId: String, weekStart: LocalDate): WeeklyStatsDTO {
        val monday = weekStart.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val sunday = monday.plusDays(6)
        val weekStartInstant = monday.atStartOfDay().toInstant(ZoneOffset.UTC)
        val weekEndInstant = sunday.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)

        val pushUpSum = WorkoutSessions.pushUpCount.sum()
        val creditsSum = WorkoutSessions.earnedTimeCredits.sum()
        val qualityAvg = WorkoutSessions.quality.avg()
        val sessionCount = WorkoutSessions.id.count()

        val weekRow = WorkoutSessions
            .select(pushUpSum, creditsSum, qualityAvg, sessionCount)
            .where {
                (WorkoutSessions.userId eq userId) and
                    (WorkoutSessions.startedAt greaterEq weekStartInstant) and
                    (WorkoutSessions.startedAt less weekEndInstant) and
                    WorkoutSessions.endedAt.isNotNull()
            }
            .first()

        return WeeklyStatsDTO(
            weekStart = monday.format(DateTimeFormatter.ISO_LOCAL_DATE),
            weekEnd = sunday.format(DateTimeFormatter.ISO_LOCAL_DATE),
            totalPushUps = weekRow[pushUpSum] ?: 0,
            totalSessions = weekRow[sessionCount].toInt(),
            totalEarnedSeconds = (weekRow[creditsSum] ?: 0).toLong(),
            averageQuality = weekRow[qualityAvg]?.toDouble(),
            dailyBreakdown = (0L..6L).map { offset -> queryDailyStats(userId, monday.plusDays(offset)) },
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
}
