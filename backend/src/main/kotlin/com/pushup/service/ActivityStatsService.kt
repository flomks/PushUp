package com.pushup.service

import com.pushup.dto.ActivityDayDTO
import com.pushup.dto.ActivityMonthlyDTO
import com.pushup.dto.ActivityStreakDTO
import com.pushup.plugins.JoggingSessions
import org.jetbrains.exposed.sql.SortOrder
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.greaterEq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.isNotNull
import org.jetbrains.exposed.sql.SqlExpressionBuilder.less
import org.jetbrains.exposed.sql.and
import org.jetbrains.exposed.sql.count
import org.jetbrains.exposed.sql.sum
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import java.util.UUID

/**
 * Service for unified activity statistics across all workout types.
 *
 * Merges data from [WorkoutSessions] (push-ups) and [JoggingSessions] tables
 * to provide activity-centric stats for the heatmap and unified streaks.
 */
class ActivityStatsService {

    // -----------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------

    /**
     * Returns monthly heatmap data: one [ActivityDayDTO] per calendar day
     * in the requested month with aggregated session counts and earned seconds
     * from all workout types.
     */
    suspend fun getMonthlyHeatmap(userId: UUID, month: Int, year: Int): ActivityMonthlyDTO =
        newSuspendedTransaction {
            val firstDay = LocalDate.of(year, month, 1)
            val lastDay = firstDay.with(TemporalAdjusters.lastDayOfMonth())
            val from = firstDay.atStartOfDay().toInstant(ZoneOffset.UTC)
            val to = lastDay.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)

            // Fetch per-day aggregates from both tables
            val workoutByDay = fetchWorkoutDailyAggregates(userId, from, to)
            val joggingByDay = fetchJoggingDailyAggregates(userId, from, to)

            // Merge into unified per-day data
            val allDates = generateSequence(firstDay) { it.plusDays(1) }
                .takeWhile { !it.isAfter(lastDay) }
                .toList()

            val days = allDates.map { date ->
                val workout = workoutByDay[date]
                val jogging = joggingByDay[date]
                ActivityDayDTO(
                    date = date.format(ISO_DATE),
                    totalSessions = (workout?.first ?: 0) + (jogging?.first ?: 0),
                    totalEarnedSeconds = (workout?.second ?: 0L) + (jogging?.second ?: 0L),
                )
            }

            ActivityMonthlyDTO(
                month = month,
                year = year,
                days = days,
                activeDays = days.count { it.totalSessions > 0 },
                totalSessions = days.sumOf { it.totalSessions },
                totalEarnedSeconds = days.sumOf { it.totalEarnedSeconds },
            )
        }

    /**
     * Returns the unified activity streak across all workout types.
     */
    suspend fun getActivityStreak(
        userId: UUID,
        today: LocalDate = LocalDate.now(ZoneOffset.UTC),
    ): ActivityStreakDTO = newSuspendedTransaction {
        // Distinct dates from workout sessions
        val workoutDays: List<LocalDate> = WorkoutSessions
            .select(WorkoutSessions.startedAtDay)
            .where {
                (WorkoutSessions.userId eq userId) and
                    WorkoutSessions.endedAt.isNotNull()
            }
            .withDistinct()
            .orderBy(WorkoutSessions.startedAtDay to SortOrder.ASC)
            .map { it[WorkoutSessions.startedAtDay].atZone(ZoneOffset.UTC).toLocalDate() }

        // Distinct dates from jogging sessions
        val joggingDays: List<LocalDate> = JoggingSessions
            .select(JoggingSessions.startedAtDay)
            .where {
                (JoggingSessions.userId eq userId) and
                    JoggingSessions.endedAt.isNotNull()
            }
            .withDistinct()
            .orderBy(JoggingSessions.startedAtDay to SortOrder.ASC)
            .map { it[JoggingSessions.startedAtDay].atZone(ZoneOffset.UTC).toLocalDate() }

        // Merge, deduplicate, sort
        val allDays = (workoutDays + joggingDays).distinct().sorted()

        if (allDays.isEmpty()) {
            return@newSuspendedTransaction ActivityStreakDTO(
                currentStreak = 0,
                longestStreak = 0,
                lastActivityDate = null,
            )
        }

        val descending = allDays.asReversed()

        ActivityStreakDTO(
            currentStreak = calculateCurrentStreak(descending, today),
            longestStreak = calculateLongestStreak(allDays),
            lastActivityDate = descending.first().format(ISO_DATE),
        )
    }

    // -----------------------------------------------------------------------
    // Private DB helpers
    // -----------------------------------------------------------------------

    /** Returns Map<LocalDate, Pair<sessionCount, earnedSeconds>> from workout_sessions. */
    private fun fetchWorkoutDailyAggregates(
        userId: UUID,
        from: Instant,
        to: Instant,
    ): Map<LocalDate, Pair<Int, Long>> {
        val sessionCount = WorkoutSessions.id.count()
        val creditsSum = WorkoutSessions.earnedTimeCredits.sum()

        return WorkoutSessions
            .select(WorkoutSessions.startedAtDay, sessionCount, creditsSum)
            .where {
                (WorkoutSessions.userId eq userId) and
                    (WorkoutSessions.startedAt greaterEq from) and
                    (WorkoutSessions.startedAt less to) and
                    WorkoutSessions.endedAt.isNotNull()
            }
            .groupBy(WorkoutSessions.startedAtDay)
            .associate { row ->
                val date = row[WorkoutSessions.startedAtDay].atZone(ZoneOffset.UTC).toLocalDate()
                date to Pair(
                    row[sessionCount].toInt(),
                    (row[creditsSum] ?: 0).toLong(),
                )
            }
    }

    /** Returns Map<LocalDate, Pair<sessionCount, earnedSeconds>> from jogging_sessions. */
    private fun fetchJoggingDailyAggregates(
        userId: UUID,
        from: Instant,
        to: Instant,
    ): Map<LocalDate, Pair<Int, Long>> {
        val fromOffset = OffsetDateTime.ofInstant(from, ZoneOffset.UTC)
        val toOffset = OffsetDateTime.ofInstant(to, ZoneOffset.UTC)
        val sessionCount = JoggingSessions.id.count()
        val creditsSum = JoggingSessions.earnedTimeCredits.sum()

        return JoggingSessions
            .select(JoggingSessions.startedAtDay, sessionCount, creditsSum)
            .where {
                (JoggingSessions.userId eq userId) and
                    (JoggingSessions.startedAt greaterEq fromOffset) and
                    (JoggingSessions.startedAt less toOffset) and
                    JoggingSessions.endedAt.isNotNull()
            }
            .groupBy(JoggingSessions.startedAtDay)
            .associate { row ->
                val date = row[JoggingSessions.startedAtDay].atZone(ZoneOffset.UTC).toLocalDate()
                date to Pair(
                    row[sessionCount].toInt(),
                    (row[creditsSum] ?: 0).toLong(),
                )
            }
    }

    // -----------------------------------------------------------------------
    // Pure streak helpers (same logic as StatsService)
    // -----------------------------------------------------------------------

    private fun calculateCurrentStreak(
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

    private fun calculateLongestStreak(workoutDaysSortedAsc: List<LocalDate>): Int {
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

    companion object {
        private val ISO_DATE: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE
    }
}
