package com.pushup.data.repository

import com.pushup.data.mapper.toDomain
import com.pushup.db.JoggingSession as DbJoggingSession
import com.pushup.db.PushUpDatabase
import com.pushup.db.WorkoutSession as DbWorkoutSession
import com.pushup.domain.model.ActivityDayStats
import com.pushup.domain.model.ExerciseType
import com.pushup.domain.model.MonthlyActivitySummary
import com.pushup.domain.model.StreakCalculator
import com.pushup.domain.repository.ActivityStatsRepository
import com.pushup.domain.repository.DailyCreditSnapshotRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime

/**
 * Local-first implementation of [ActivityStatsRepository].
 *
 * Merges data from WorkoutSession (push-ups) and JoggingSession tables
 * to produce unified activity statistics for heatmap rendering and streak
 * calculation.
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
            val workoutRows: List<DbWorkoutSession> = queries.selectWorkoutSessionsByDateRangeExclusive(
                userId = userId,
                startedAt = fromMs,
                startedAt_ = toMs,
            ).executeAsList()
            val workoutSessions = workoutRows.map { session -> session.toDomain() }

            // Query completed jogging sessions for this month
            val joggingRows: List<DbJoggingSession> = queries.selectJoggingSessionsByDateRange(
                userId = userId,
                startedAt = fromMs,
                startedAt_ = toMs,
            ).executeAsList()
            val joggingSessions = joggingRows
                .filter { row -> row.endedAt != null && row.distanceMeters > 0.0 }
                .map { session -> session.toDomain() }

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

            // Get distinct workout dates by querying all completed sessions
            // and extracting dates in Kotlin (avoids SQLite date() type issues)
            val workoutRows: List<DbWorkoutSession> = queries.selectWorkoutSessionsByUserId(userId)
                .executeAsList()
            val workoutDates = workoutRows
                .filter { it.endedAt != null }
                .map { Instant.fromEpochMilliseconds(it.startedAt).toLocalDateTime(timeZone).date }
                .distinct()

            // Get distinct jogging dates
            val joggingRows: List<DbJoggingSession> = queries.selectJoggingSessionsByUserId(userId)
                .executeAsList()
            val joggingDates = joggingRows
                .filter { it.endedAt != null && it.distanceMeters > 0.0 }
                .map { Instant.fromEpochMilliseconds(it.startedAt).toLocalDateTime(timeZone).date }
                .distinct()

            // Merge, deduplicate, sort
            val allDates = (workoutDates + joggingDates).distinct().sorted()

            StreakCalculator.calculateStreaks(allDates, today)
        }
    }
}
