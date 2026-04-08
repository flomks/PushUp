package com.pushup.data.repository

import com.pushup.data.api.KtorApiClient
import com.pushup.data.mapper.toDomain
import com.pushup.db.JoggingSession as DbJoggingSession
import com.pushup.db.PushUpDatabase
import com.pushup.db.WorkoutSession as DbWorkoutSession
import com.pushup.domain.model.DailyStats
import com.pushup.domain.model.ExerciseType
import com.pushup.domain.model.LevelCalculator
import com.pushup.domain.model.MonthlyStats
import com.pushup.domain.model.StreakCalculator
import com.pushup.domain.model.TotalStats
import com.pushup.domain.model.WeeklyStats
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.StatsRepository
import com.pushup.domain.repository.TimeCreditRepository
import com.pushup.domain.usecase.sync.NetworkMonitor
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.Instant
import kotlinx.datetime.DayOfWeek
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.minus
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime

/**
 * SQLDelight-backed implementation of [StatsRepository] with optional
 * Ktor API fallback for faster aggregation on large datasets.
 *
 * ## Dual-source strategy
 * Statistics can be computed from two sources:
 *
 * 1. **Local SQLite** (always available, offline-safe): Aggregates [WorkoutSession]
 *    data in memory. Correct for moderate data volumes typical in a personal
 *    fitness app.
 *
 * 2. **Ktor backend API** (optional, requires network): The custom Ktor backend
 *    pre-aggregates data in PostgreSQL, which is significantly faster when the
 *    user has thousands of sessions. This is the preferred source when available.
 *
 * ## Source selection
 * When [ktorApiClient] and [networkMonitor] are provided:
 * - If the device is **online**, the Ktor API is tried first.
 * - If the API call succeeds, the result is returned immediately.
 * - If the API call fails (network error, server error, etc.), the implementation
 *   falls back to local computation transparently.
 * - If the device is **offline**, local computation is used directly.
 *
 * When [ktorApiClient] or [networkMonitor] is `null`, local computation is
 * always used (same behaviour as the original implementation).
 *
 * ## Cache strategy
 * Local data is the source of truth. The API result is used as a read-through
 * cache for performance -- it is never written back to the local DB by this
 * repository. The sync use-cases ([SyncFromCloudUseCase]) are responsible for
 * keeping the local DB up-to-date.
 *
 * All suspend functions are main-safe -- dispatcher switching is handled
 * by [safeDbCall].
 *
 * @param database The SQLDelight-generated [PushUpDatabase] instance.
 * @param timeCreditRepository Repository for reading the user's time credit balance.
 * @param dispatcher The [CoroutineDispatcher] used for database I/O.
 * @param timeZone The timezone for date-based aggregation. Must be provided
 *   explicitly to ensure deterministic behaviour across devices.
 * @param clock Clock used to determine "today" for streak calculation.
 * @param ktorApiClient Optional Ktor backend client for server-side aggregation.
 * @param networkMonitor Optional network connectivity checker.
 */
class StatsRepositoryImpl(
    private val database: PushUpDatabase,
    private val timeCreditRepository: TimeCreditRepository,
    private val dispatcher: CoroutineDispatcher,
    private val timeZone: TimeZone = TimeZone.currentSystemDefault(),
    private val clock: Clock = Clock.System,
    private val ktorApiClient: KtorApiClient? = null,
    private val networkMonitor: NetworkMonitor? = null,
) : StatsRepository {

    private val queries get() = database.databaseQueries

    /**
     * Returns daily stats for [date].
     *
     * Always computes from the local SQLite database for instant results.
     * The Ktor API is intentionally not consulted on the read path to avoid
     * network latency blocking the UI. The local DB is the source of truth;
     * sync use-cases keep it up-to-date in the background.
     */
    override suspend fun getDailyStats(userId: String, date: LocalDate): DailyStats? {
        return safeDbCall(dispatcher, "Failed to get daily stats for user '$userId' on $date") {
            val sessions = querySessionsForDateRange(
                userId = userId,
                from = date,
                toExclusive = date.plus(1, DateTimeUnit.DAY),
            )
            if (sessions.isEmpty()) return@safeDbCall null
            buildDailyStats(date, sessions)
        }
    }

    /**
     * Returns weekly stats for the week starting on [weekStart].
     *
     * Always computes from the local SQLite database for instant results.
     */
    override suspend fun getWeeklyStats(userId: String, weekStart: LocalDate): WeeklyStats? {
        return safeDbCall(
            dispatcher,
            "Failed to get weekly stats for user '$userId' starting $weekStart",
        ) {
            val weekEnd = weekStart.plus(7, DateTimeUnit.DAY)
            val sessions = querySessionsForDateRange(
                userId = userId,
                from = weekStart,
                toExclusive = weekEnd,
            )
            if (sessions.isEmpty()) return@safeDbCall null

            // Group sessions by day once -- O(n) instead of O(n*days)
            val sessionsByDay = sessions.groupBy { it.date }

            val dailyBreakdown = (0 until 7).map { offset ->
                val day = weekStart.plus(offset, DateTimeUnit.DAY)
                buildDailyStats(day, sessionsByDay[day].orEmpty())
            }

            WeeklyStats(
                weekStartDate = weekStart,
                totalActivityXp = sessions.sumOf { it.activityXp },
                totalSessions = sessions.size,
                totalEarnedSeconds = sessions.sumOf { it.earnedSeconds },
                averageActivityXpPerSession = averageActivityXp(sessions),
                bestSessionActivityXp = sessions.maxOfOrNull { it.activityXp } ?: 0L,
                dailyBreakdown = dailyBreakdown,
            )
        }
    }

    /**
     * Returns monthly stats for [month]/[year].
     *
     * Always computes from the local SQLite database for instant results.
     */
    override suspend fun getMonthlyStats(userId: String, month: Int, year: Int): MonthlyStats? {
        return safeDbCall(
            dispatcher,
            "Failed to get monthly stats for user '$userId' ($month/$year)",
        ) {
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
            if (sessions.isEmpty()) return@safeDbCall null

            val weeklyBreakdown = buildWeeklyBreakdown(sessions, monthStart, monthEnd)

            MonthlyStats(
                month = month,
                year = year,
                totalActivityXp = sessions.sumOf { it.activityXp },
                totalSessions = sessions.size,
                totalEarnedSeconds = sessions.sumOf { it.earnedSeconds },
                averageActivityXpPerSession = averageActivityXp(sessions),
                bestSessionActivityXp = sessions.maxOfOrNull { it.activityXp } ?: 0L,
                weeklyBreakdown = weeklyBreakdown,
            )
        }
    }

    /**
     * Returns all-time stats for [userId].
     *
     * Always computes from the local SQLite database for instant results.
     */
    override suspend fun getTotalStats(userId: String): TotalStats? {
        return safeDbCall(
            dispatcher,
            "Failed to get total stats for user '$userId'",
        ) {
            val sessions = queryAllSessions(userId)
            if (sessions.isEmpty()) return@safeDbCall null

            val timeCredit = timeCreditRepository.get(userId)

            val today = clock.now().toLocalDateTime(timeZone).date

            val allDates = sessions
                .map { it.date }
                .distinct()
                .sorted()

            val (currentStreak, longestStreak) = calculateStreaks(allDates, today)

            val avgQuality = sessions
                .mapNotNull { it.quality?.toDouble() }
                .average()
                .toFloat()
                .takeIf { !it.isNaN() } ?: 0f

            TotalStats(
                userId = userId,
                totalActivityXp = sessions.sumOf { it.activityXp },
                totalSessions = sessions.size,
                totalEarnedSeconds = timeCredit?.totalEarnedSeconds
                    ?: sessions.sumOf { it.earnedSeconds },
                totalSpentSeconds = timeCredit?.totalSpentSeconds ?: 0L,
                averageQuality = avgQuality,
                averageActivityXpPerSession = averageActivityXp(sessions),
                bestSessionActivityXp = sessions.maxOfOrNull { it.activityXp } ?: 0L,
                currentStreakDays = currentStreak,
                longestStreakDays = longestStreak,
            )
        }
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    /**
     * Queries sessions whose `startedAt` falls within `[from, toExclusive)`.
     *
     * Uses the exclusive upper-bound query (`startedAt < ?`) to avoid
     * off-by-one issues at date boundaries.
     */
    private fun querySessionsForDateRange(
        userId: String,
        from: LocalDate,
        toExclusive: LocalDate,
    ): List<ActivitySessionStats> {
        val fromMs = from.atStartOfDayIn(timeZone).toEpochMilliseconds()
        val toMs = toExclusive.atStartOfDayIn(timeZone).toEpochMilliseconds()
        val workoutRows: List<DbWorkoutSession> = queries.selectWorkoutSessionsByDateRangeExclusive(
            userId = userId,
            startedAt = fromMs,
            startedAt_ = toMs,
        ).executeAsList()
        val workoutSessions = workoutRows.map { row -> row.toDomain().toActivityStats() }

        val joggingRows: List<DbJoggingSession> = queries.selectJoggingSessionsByDateRange(
            userId = userId,
            startedAt = fromMs,
            startedAt_ = toMs,
        ).executeAsList()
        val joggingSessions = joggingRows
            .filter { row -> row.endedAt != null && row.distanceMeters > 0.0 }
            .map { row -> row.toActivityStats() }

        return (workoutSessions + joggingSessions).sortedBy { it.date }
    }

    /**
     * Extracts the [LocalDate] from a session's [WorkoutSession.startedAt].
     */
    private fun sessionDate(session: WorkoutSession): LocalDate =
        session.startedAt.toLocalDateTime(timeZone).date

    private fun queryAllSessions(userId: String): List<ActivitySessionStats> {
        val workoutRows: List<DbWorkoutSession> = queries.selectWorkoutSessionsByUserId(userId)
            .executeAsList()
        val workoutSessions = workoutRows
            .filter { row -> row.endedAt != null && row.pushUpCount > 0 }
            .map { row -> row.toDomain().toActivityStats() }

        val joggingRows: List<DbJoggingSession> = queries.selectJoggingSessionsByUserId(userId)
            .executeAsList()
        val joggingSessions = joggingRows
            .filter { row -> row.endedAt != null && row.distanceMeters > 0.0 }
            .map { row -> row.toActivityStats() }

        return (workoutSessions + joggingSessions).sortedBy { it.date }
    }

    /**
     * Builds a [DailyStats] from a date and its associated sessions in a single pass.
     * Returns a zero-activity entry when [sessions] is empty.
     */
    private fun buildDailyStats(date: LocalDate, sessions: List<ActivitySessionStats>): DailyStats {
        if (sessions.isEmpty()) {
            return DailyStats(
                date = date,
                totalActivityXp = 0L,
                totalSessions = 0,
                totalEarnedSeconds = 0L,
                averageQuality = 0f,
                averageActivityXpPerSession = 0f,
                bestSessionActivityXp = 0L,
            )
        }

        var totalActivityXp = 0L
        var totalEarnedSeconds = 0L
        var qualitySum = 0.0
        var qualityCount = 0
        var bestSessionActivityXp = 0L

        for (session in sessions) {
            totalActivityXp += session.activityXp
            totalEarnedSeconds += session.earnedSeconds
            if (session.quality != null) {
                qualitySum += session.quality
                qualityCount++
            }
            if (session.activityXp > bestSessionActivityXp) bestSessionActivityXp = session.activityXp
        }

        val count = sessions.size
        return DailyStats(
            date = date,
            totalActivityXp = totalActivityXp,
            totalSessions = count,
            totalEarnedSeconds = totalEarnedSeconds,
            averageQuality = if (qualityCount > 0) (qualitySum / qualityCount).toFloat() else 0f,
            averageActivityXpPerSession = totalActivityXp.toFloat() / count,
            bestSessionActivityXp = bestSessionActivityXp,
        )
    }

    /**
     * Builds weekly breakdown for a month, grouping sessions by the Monday
     * of their respective ISO week.
     *
     * Sessions are grouped by date once (O(n)) and then distributed into
     * weeks and days without repeated filtering.
     */
    private fun buildWeeklyBreakdown(
        sessions: List<ActivitySessionStats>,
        monthStart: LocalDate,
        monthEnd: LocalDate,
    ): List<WeeklyStats> {
        val sessionsByDay: Map<LocalDate, List<ActivitySessionStats>> = sessions.groupBy { it.date }

        // Collect the Monday of every ISO week that overlaps with the month
        val weekStarts = mutableSetOf<LocalDate>()
        var current = mondayOf(monthStart)
        while (current < monthEnd) {
            weekStarts.add(current)
            current = current.plus(7, DateTimeUnit.DAY)
        }

        return weekStarts.sorted().map { weekStart ->
            // Single pass: build daily breakdown and accumulate week-level aggregates together
            val dailyBreakdown = ArrayList<DailyStats>(7)
            val weekSessions = ArrayList<ActivitySessionStats>()

            for (offset in 0 until 7) {
                val day = weekStart.plus(offset, DateTimeUnit.DAY)
                val daySessions = sessionsByDay[day].orEmpty()
                weekSessions.addAll(daySessions)
                dailyBreakdown.add(buildDailyStats(day, daySessions))
            }

            WeeklyStats(
                weekStartDate = weekStart,
                totalActivityXp = weekSessions.sumOf { it.activityXp },
                totalSessions = weekSessions.size,
                totalEarnedSeconds = weekSessions.sumOf { it.earnedSeconds },
                averageActivityXpPerSession = averageActivityXp(weekSessions),
                bestSessionActivityXp = weekSessions.maxOfOrNull { it.activityXp } ?: 0L,
                dailyBreakdown = dailyBreakdown,
            )
        }
    }

    /**
     * Returns the Monday of the ISO week containing [date].
     */
    private fun mondayOf(date: LocalDate): LocalDate {
        @Suppress("REDUNDANT_ELSE_IN_WHEN")
        val daysFromMonday = when (date.dayOfWeek) {
            DayOfWeek.MONDAY -> 0
            DayOfWeek.TUESDAY -> 1
            DayOfWeek.WEDNESDAY -> 2
            DayOfWeek.THURSDAY -> 3
            DayOfWeek.FRIDAY -> 4
            DayOfWeek.SATURDAY -> 5
            DayOfWeek.SUNDAY -> 6
            else -> 0 // required for commonMain: expect enum cannot be exhaustive without else
        }
        return date.minus(daysFromMonday, DateTimeUnit.DAY)
    }

    /**
     * Delegates to [StreakCalculator] for streak computation.
     * Kept as an internal method for backward compatibility with existing tests.
     */
    internal fun calculateStreaks(sortedDates: List<LocalDate>, today: LocalDate): Pair<Int, Int> =
        StreakCalculator.calculateStreaks(sortedDates, today)

    /**
     * Returns the average push-ups per session, or `0f` when [sessions] is empty.
     */
    private fun averageActivityXp(sessions: List<ActivitySessionStats>): Float =
        if (sessions.isEmpty()) 0f
        else sessions.sumOf { it.activityXp }.toFloat() / sessions.size

    private fun WorkoutSession.toActivityStats(): ActivitySessionStats =
        ActivitySessionStats(
            date = sessionDate(this),
            earnedSeconds = earnedTimeCreditSeconds,
            activityXp = LevelCalculator.calculateExerciseXp(
                exerciseType = ExerciseType.PUSH_UPS,
                amount = pushUpCount,
                quality = quality,
            ),
            quality = quality,
        )

    private fun DbJoggingSession.toActivityStats(): ActivitySessionStats {
        val distanceUnits = (distanceMeters / 100.0).toInt()
        return ActivitySessionStats(
            date = Instant.fromEpochMilliseconds(startedAt).toLocalDateTime(timeZone).date,
            earnedSeconds = earnedTimeCredits,
            activityXp = LevelCalculator.calculateExerciseXp(
                exerciseType = ExerciseType.JOGGING,
                amount = distanceUnits,
            ),
            quality = null,
        )
    }

    private data class ActivitySessionStats(
        val date: LocalDate,
        val earnedSeconds: Long,
        val activityXp: Long,
        val quality: Float?,
    )
}
