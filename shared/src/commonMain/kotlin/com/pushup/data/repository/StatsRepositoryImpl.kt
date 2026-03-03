package com.pushup.data.repository

import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.DailyStats
import com.pushup.domain.model.MonthlyStats
import com.pushup.domain.model.TotalStats
import com.pushup.domain.model.WeeklyStats
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.StatsRepository
import com.pushup.domain.repository.TimeCreditRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.DayOfWeek
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.minus
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime

/**
 * SQLDelight-backed implementation of [StatsRepository].
 *
 * Computes aggregated statistics by querying [WorkoutSession] data from the
 * database and grouping/aggregating in memory. This approach is correct for
 * moderate data volumes typical in a personal fitness app; if the data set
 * grows significantly, the aggregation can be pushed down to SQL.
 *
 * All suspend functions switch to [dispatcher] to keep callers main-safe.
 *
 * @param database The SQLDelight-generated [PushUpDatabase] instance.
 * @param timeCreditRepository Repository for reading the user's time credit balance.
 * @param dispatcher The [CoroutineDispatcher] used for database I/O.
 * @param timeZone The timezone for date-based aggregation. Defaults to [TimeZone.currentSystemDefault].
 */
class StatsRepositoryImpl(
    private val database: PushUpDatabase,
    private val timeCreditRepository: TimeCreditRepository,
    private val dispatcher: CoroutineDispatcher,
    private val timeZone: TimeZone = TimeZone.currentSystemDefault(),
) : StatsRepository {

    private val queries get() = database.databaseQueries

    override suspend fun getDailyStats(userId: String, date: LocalDate): DailyStats? =
        withContext(dispatcher) {
            try {
                val sessions = querySessionsForDateRange(
                    userId = userId,
                    from = date,
                    toExclusive = date.plus(1, DateTimeUnit.DAY),
                )
                if (sessions.isEmpty()) return@withContext null
                buildDailyStats(date, sessions)
            } catch (e: Exception) {
                throw RepositoryException(
                    "Failed to get daily stats for user '$userId' on $date",
                    e,
                )
            }
        }

    override suspend fun getWeeklyStats(userId: String, weekStart: LocalDate): WeeklyStats? =
        withContext(dispatcher) {
            try {
                val weekEnd = weekStart.plus(7, DateTimeUnit.DAY)
                val sessions = querySessionsForDateRange(
                    userId = userId,
                    from = weekStart,
                    toExclusive = weekEnd,
                )
                if (sessions.isEmpty()) return@withContext null

                val dailyBreakdown = (0 until 7).map { offset ->
                    val day = weekStart.plus(offset, DateTimeUnit.DAY)
                    val daySessions = sessions.filter { sessionDate(it) == day }
                    buildDailyStats(day, daySessions)
                }

                WeeklyStats(
                    weekStartDate = weekStart,
                    totalPushUps = sessions.sumOf { it.pushUpCount },
                    totalSessions = sessions.size,
                    totalEarnedSeconds = sessions.sumOf { it.earnedTimeCreditSeconds },
                    dailyBreakdown = dailyBreakdown,
                )
            } catch (e: Exception) {
                throw RepositoryException(
                    "Failed to get weekly stats for user '$userId' starting $weekStart",
                    e,
                )
            }
        }

    override suspend fun getMonthlyStats(userId: String, month: Int, year: Int): MonthlyStats? =
        withContext(dispatcher) {
            try {
                val monthStart = LocalDate(year, month, 1)
                val monthEnd = if (month == 12) {
                    LocalDate(year + 1, 1, 1)
                } else {
                    LocalDate(year, month + 1, 1)
                }

                val sessions = querySessionsForDateRange(
                    userId = userId,
                    from = monthStart,
                    toExclusive = monthEnd,
                )
                if (sessions.isEmpty()) return@withContext null

                // Group sessions into ISO weeks
                val weeklyBreakdown = buildWeeklyBreakdown(sessions, monthStart, monthEnd)

                MonthlyStats(
                    month = month,
                    year = year,
                    totalPushUps = sessions.sumOf { it.pushUpCount },
                    totalSessions = sessions.size,
                    totalEarnedSeconds = sessions.sumOf { it.earnedTimeCreditSeconds },
                    weeklyBreakdown = weeklyBreakdown,
                )
            } catch (e: Exception) {
                throw RepositoryException(
                    "Failed to get monthly stats for user '$userId' ($month/$year)",
                    e,
                )
            }
        }

    override suspend fun getTotalStats(userId: String): TotalStats? = withContext(dispatcher) {
        try {
            val sessions = queries.selectWorkoutSessionsByUserId(userId)
                .executeAsList()
                .map { it.toDomain() }

            if (sessions.isEmpty()) return@withContext null

            val timeCredit = timeCreditRepository.get(userId)

            val sessionDates = sessions
                .map { sessionDate(it) }
                .distinct()
                .sorted()

            val (currentStreak, longestStreak) = calculateStreaks(sessionDates)

            val avgQuality = sessions.map { it.quality }.average().toFloat()

            TotalStats(
                userId = userId,
                totalPushUps = sessions.sumOf { it.pushUpCount },
                totalSessions = sessions.size,
                totalEarnedSeconds = timeCredit?.totalEarnedSeconds
                    ?: sessions.sumOf { it.earnedTimeCreditSeconds },
                totalSpentSeconds = timeCredit?.totalSpentSeconds ?: 0L,
                averageQuality = avgQuality,
                currentStreakDays = currentStreak,
                longestStreakDays = longestStreak,
            )
        } catch (e: Exception) {
            throw RepositoryException("Failed to get total stats for user '$userId'", e)
        }
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    /**
     * Queries sessions whose `startedAt` falls within `[from, toExclusive)`.
     */
    private fun querySessionsForDateRange(
        userId: String,
        from: LocalDate,
        toExclusive: LocalDate,
    ): List<WorkoutSession> {
        val fromMs = from.atStartOfDayIn(timeZone).toEpochMilliseconds()
        val toMs = toExclusive.atStartOfDayIn(timeZone).toEpochMilliseconds() - 1
        return queries.selectWorkoutSessionsByDateRange(
            userId = userId,
            startedAt = fromMs,
            startedAt_ = toMs,
        ).executeAsList().map { it.toDomain() }
    }

    /**
     * Extracts the [LocalDate] from a session's [WorkoutSession.startedAt].
     */
    private fun sessionDate(session: WorkoutSession): LocalDate =
        session.startedAt.toLocalDateTime(timeZone).date

    /**
     * Builds a [DailyStats] from a date and its associated sessions.
     * Returns a zero-activity entry when [sessions] is empty.
     */
    private fun buildDailyStats(date: LocalDate, sessions: List<WorkoutSession>): DailyStats {
        if (sessions.isEmpty()) {
            return DailyStats(
                date = date,
                totalPushUps = 0,
                totalSessions = 0,
                totalEarnedSeconds = 0L,
                averageQuality = 0f,
            )
        }
        return DailyStats(
            date = date,
            totalPushUps = sessions.sumOf { it.pushUpCount },
            totalSessions = sessions.size,
            totalEarnedSeconds = sessions.sumOf { it.earnedTimeCreditSeconds },
            averageQuality = sessions.map { it.quality }.average().toFloat(),
        )
    }

    /**
     * Builds weekly breakdown for a month, grouping sessions by the Monday
     * of their respective ISO week.
     */
    private fun buildWeeklyBreakdown(
        sessions: List<WorkoutSession>,
        monthStart: LocalDate,
        monthEnd: LocalDate,
    ): List<WeeklyStats> {
        // Find all distinct week-start dates (Mondays) that cover the month
        val weekStarts = mutableSetOf<LocalDate>()
        var current = mondayOf(monthStart)
        while (current < monthEnd) {
            weekStarts.add(current)
            current = current.plus(7, DateTimeUnit.DAY)
        }

        return weekStarts.sorted().map { weekStart ->
            val weekEnd = weekStart.plus(7, DateTimeUnit.DAY)
            val weekSessions = sessions.filter { s ->
                val d = sessionDate(s)
                d >= weekStart && d < weekEnd
            }
            val dailyBreakdown = (0 until 7).map { offset ->
                val day = weekStart.plus(offset, DateTimeUnit.DAY)
                val daySessions = weekSessions.filter { sessionDate(it) == day }
                buildDailyStats(day, daySessions)
            }
            WeeklyStats(
                weekStartDate = weekStart,
                totalPushUps = weekSessions.sumOf { it.pushUpCount },
                totalSessions = weekSessions.size,
                totalEarnedSeconds = weekSessions.sumOf { it.earnedTimeCreditSeconds },
                dailyBreakdown = dailyBreakdown,
            )
        }
    }

    /**
     * Returns the Monday of the ISO week containing [date].
     */
    private fun mondayOf(date: LocalDate): LocalDate {
        val daysFromMonday = when (date.dayOfWeek) {
            DayOfWeek.MONDAY -> 0
            DayOfWeek.TUESDAY -> 1
            DayOfWeek.WEDNESDAY -> 2
            DayOfWeek.THURSDAY -> 3
            DayOfWeek.FRIDAY -> 4
            DayOfWeek.SATURDAY -> 5
            DayOfWeek.SUNDAY -> 6
        }
        return date.minus(daysFromMonday, DateTimeUnit.DAY)
    }

    /**
     * Calculates the current and longest streak from a sorted list of distinct
     * dates that had at least one session.
     *
     * @return Pair of (currentStreak, longestStreak)
     */
    private fun calculateStreaks(sortedDates: List<LocalDate>): Pair<Int, Int> {
        if (sortedDates.isEmpty()) return 0 to 0

        var longestStreak = 1
        var currentStreak = 1

        for (i in 1 until sortedDates.size) {
            val expectedNext = sortedDates[i - 1].plus(1, DateTimeUnit.DAY)
            if (sortedDates[i] == expectedNext) {
                currentStreak++
            } else {
                if (currentStreak > longestStreak) longestStreak = currentStreak
                currentStreak = 1
            }
        }
        if (currentStreak > longestStreak) longestStreak = currentStreak

        return currentStreak to longestStreak
    }
}
