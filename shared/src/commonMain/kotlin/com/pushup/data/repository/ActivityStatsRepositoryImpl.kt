package com.pushup.data.repository

import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.ActivityDayStats
import com.pushup.domain.model.ExerciseType
import com.pushup.domain.model.MonthlyActivitySummary
import com.pushup.domain.model.StreakCalculator
import com.pushup.domain.repository.ActivityStatsRepository
import com.pushup.domain.repository.DailyCreditSnapshotRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime

/**
 * Local-first implementation of [ActivityStatsRepository].
 *
 * Merges data from [WorkoutSession] (push-ups) and [JoggingSession] tables
 * to produce unified activity statistics for heatmap rendering and streak
 * calculation.
 *
 * ## Data source strategy for heatmap
 * 1. Query both WorkoutSession and JoggingSession tables for the month.
 * 2. Group by date and merge into [ActivityDayStats] entries.
 * 3. Fill in zero-activity days so the UI gets a complete calendar grid.
 *
 * ## Streak calculation
 * Queries distinct dates from both tables, merges them, and delegates
 * to [StreakCalculator] for the actual computation.
 */
class ActivityStatsRepositoryImpl(
    private val database: PushUpDatabase,
    private val snapshotRepository: DailyCreditSnapshotRepository,
    private val dispatcher: CoroutineDispatcher,
    private val timeZone: TimeZone = TimeZone.currentSystemDefault(),
    private val clock: Clock = Clock.System,
) : ActivityStatsRepository {

    private val queries get() = database.databaseQueries

    override suspend fun getMonthlyActivity(
        userId: String,
        month: Int,
        year: Int,
    ): MonthlyActivitySummary {
        return safeDbCall(
            dispatcher,
            "Failed to get monthly activity for user '$userId' ($month/$year)",
        ) {
            val monthStart = LocalDate(year, month, 1)
            val monthEnd = if (month == 12) {
                LocalDate(year + 1, 1, 1)
            } else {
                LocalDate(year, month + 1, 1)
            }

            val fromMs = monthStart.atStartOfDayIn(timeZone).toEpochMilliseconds()
            val toMs = monthEnd.atStartOfDayIn(timeZone).toEpochMilliseconds()

            // Query workout sessions (push-ups) for this month
            val workoutSessions = queries.selectWorkoutSessionsByDateRangeExclusive(
                userId = userId,
                startedAt = fromMs,
                startedAt_ = toMs,
            ).executeAsList().map { it.toDomain() }

            // Query jogging sessions for this month
            val joggingSessions = queries.selectJoggingSessionsByDateRangeExclusive(
                userId = userId,
                startedAt = fromMs,
                startedAt_ = toMs,
            ).executeAsList().map { it.toDomain() }

            // Group workout sessions by date
            val workoutByDate = workoutSessions.groupBy { session ->
                session.startedAt.toLocalDateTime(timeZone).date
            }

            // Group jogging sessions by date
            val joggingByDate = joggingSessions.groupBy { session ->
                session.startedAt.toLocalDateTime(timeZone).date
            }

            // All dates in the month
            val allDates = mutableListOf<LocalDate>()
            var current = monthStart
            while (current < monthEnd) {
                allDates.add(current)
                current = current.plus(1, DateTimeUnit.DAY)
            }

            // Build ActivityDayStats for each day
            val days = allDates.map { date ->
                val dayWorkouts = workoutByDate[date].orEmpty()
                val dayJogging = joggingByDate[date].orEmpty()

                val totalSessions = dayWorkouts.size + dayJogging.size
                val totalEarned = dayWorkouts.sumOf { it.earnedTimeCreditSeconds } +
                    dayJogging.sumOf { it.earnedTimeCreditSeconds }

                val types = mutableSetOf<ExerciseType>()
                if (dayWorkouts.isNotEmpty()) types.add(ExerciseType.PUSH_UPS)
                if (dayJogging.isNotEmpty()) types.add(ExerciseType.JOGGING)

                ActivityDayStats(
                    date = date,
                    totalSessions = totalSessions,
                    totalEarnedSeconds = totalEarned,
                    workoutTypes = types,
                )
            }

            MonthlyActivitySummary(
                month = month,
                year = year,
                days = days,
            )
        }
    }

    override suspend fun getActivityStreak(userId: String): Pair<Int, Int> {
        return safeDbCall(
            dispatcher,
            "Failed to get activity streak for user '$userId'",
        ) {
            val today = clock.now().toLocalDateTime(timeZone).date

            // Get distinct workout dates
            val workoutDates = queries.selectDistinctWorkoutDates(userId)
                .executeAsList()
                .mapNotNull { it.sessionDate?.let(LocalDate::parse) }

            // Get distinct jogging dates
            val joggingDates = queries.selectDistinctJoggingDates(userId)
                .executeAsList()
                .mapNotNull { it.sessionDate?.let(LocalDate::parse) }

            // Merge, deduplicate, sort
            val allDates = (workoutDates + joggingDates).distinct().sorted()

            StreakCalculator.calculateStreaks(allDates, today)
        }
    }
}
