package com.pushup.di

import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.PushUpRecord
import com.pushup.domain.model.RoutePoint
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.DailyCreditSnapshotRepository
import com.pushup.domain.repository.JoggingSessionRepository
import com.pushup.domain.repository.PushUpRecordRepository
import com.pushup.domain.repository.RoutePointRepository
import com.pushup.domain.repository.TimeCreditRepository
import com.pushup.domain.repository.WorkoutSessionRepository
import com.pushup.domain.usecase.GetCreditBreakdownUseCase
import com.pushup.domain.usecase.GetDailyStatsUseCase
import com.pushup.domain.usecase.GetTimeCreditUseCase
import com.pushup.domain.usecase.GetTotalStatsUseCase
import com.pushup.domain.usecase.GetWeeklyStatsUseCase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.datetime.LocalDate
import org.koin.core.component.KoinComponent
import org.koin.core.component.get

/**
 * iOS-facing bridge that exposes KMP data operations to Swift.
 *
 * ## Why this exists
 * Kotlin Flows and suspend functions cannot be called directly from Swift.
 * This bridge wraps them in callback-based APIs that Swift can consume:
 *
 * - **Flows** are collected in a background coroutine. Each emission calls
 *   [onUpdate] on the main thread. The returned [Job] can be cancelled to
 *   stop the collection (call [Job.cancel] when the Swift view disappears).
 *
 * - **Suspend functions** are wrapped in fire-and-forget coroutines that
 *   call a completion handler when done.
 *
 * ## Threading
 * IO/network work runs on [Dispatchers.Default] to keep the main thread free.
 * All callbacks are dispatched back on [Dispatchers.Main] so Swift ViewModels
 * can update `@Published` properties without `DispatchQueue.main.async`.
 *
 * ## Usage from Swift
 * ```swift
 * // Start observing sessions — returns a Job that must be cancelled on deinit
 * let job = DataBridge.shared.observeSessions(userId: userId) { sessions in
 *     self.allSessions = sessions.map { ... }
 * }
 * // Cancel when the ViewModel is deallocated
 * deinit { job.cancel() }
 * ```
 */
object DataBridge : KoinComponent {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // =========================================================================
    // Session observation
    // =========================================================================

    /**
     * Observes all workout sessions for [userId] from the local SQLite database.
     *
     * The [onUpdate] callback is called immediately with the current list and
     * again whenever the database changes (e.g. after a workout is finished).
     *
     * @return A [Job] — cancel it when the observer is no longer needed.
     */
    fun observeSessions(
        userId: String,
        onUpdate: (List<WorkoutSession>) -> Unit,
    ): Job = scope.launch {
        get<WorkoutSessionRepository>()
            .observeAllByUserId(userId)
            .catch { /* ignore errors — best-effort live updates */ }
            .collect { sessions ->
                withContext(Dispatchers.Main) { onUpdate(sessions) }
            }
    }

    // =========================================================================
    // Jogging session observation
    // =========================================================================

    /**
     * Observes all jogging sessions for [userId] from the local SQLite database.
     *
     * The [onUpdate] callback is called immediately with the current list and
     * again whenever the database changes (e.g. after a jog is finished).
     *
     * @return A [Job] — cancel it when the observer is no longer needed.
     */
    fun observeJoggingSessions(
        userId: String,
        onUpdate: (List<JoggingSession>) -> Unit,
    ): Job = scope.launch {
        get<JoggingSessionRepository>()
            .observeAllByUserId(userId)
            .catch { /* ignore errors — best-effort live updates */ }
            .collect { sessions ->
                withContext(Dispatchers.Main) { onUpdate(sessions) }
            }
    }

    // =========================================================================
    // Route points
    // =========================================================================

    /**
     * Fetches all GPS route points for a given jogging [sessionId] from the local DB.
     *
     * Route points are returned in ascending timestamp order. The callback receives
     * an empty list when no route points exist for the session.
     */
    fun fetchRoutePointsForSession(
        sessionId: String,
        onResult: (List<RoutePoint>) -> Unit,
    ) {
        scope.launch {
            try {
                val points = get<RoutePointRepository>().getBySessionId(sessionId)
                withContext(Dispatchers.Main) { onResult(points) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(emptyList()) }
            }
        }
    }

    // =========================================================================
    // Time credit observation
    // =========================================================================

    /**
     * Observes the time-credit balance for [userId] from the local SQLite database.
     *
     * The [onUpdate] callback is called immediately with the current balance and
     * again whenever it changes (e.g. after a workout earns credits).
     *
     * @return A [Job] — cancel it when the observer is no longer needed.
     */
    fun observeTimeCredit(
        userId: String,
        onUpdate: (TimeCredit?) -> Unit,
    ): Job = scope.launch {
        get<TimeCreditRepository>()
            .observeCredit(userId)
            .catch { /* ignore errors — best-effort live updates */ }
            .collect { credit ->
                withContext(Dispatchers.Main) { onUpdate(credit) }
            }
    }

    // =========================================================================
    // Push-up records
    // =========================================================================

    /**
     * Fetches all push-up records for a given [sessionId] from the local DB.
     *
     * Records are returned in ascending timestamp order. The callback receives
     * an empty list when no records exist for the session.
     */
    fun fetchRecordsForSession(
        sessionId: String,
        onResult: (List<PushUpRecord>) -> Unit,
    ) {
        scope.launch {
            try {
                val records = get<PushUpRecordRepository>().getBySessionId(sessionId)
                withContext(Dispatchers.Main) { onResult(records) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(emptyList()) }
            }
        }
    }

    // =========================================================================
    // One-shot data fetches (suspend → completionHandler)
    // =========================================================================

    /**
     * Fetches the current time-credit balance for [userId] once.
     *
     * Calls [onResult] with the [TimeCredit] (or `null` if none exists).
     */
    fun fetchTimeCredit(
        userId: String,
        onResult: (TimeCredit?) -> Unit,
    ) {
        scope.launch {
            try {
                val credit = get<GetTimeCreditUseCase>().invoke(userId)
                withContext(Dispatchers.Main) { onResult(credit) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(null) }
            }
        }
    }

    /**
     * Fetches a detailed breakdown of the current daily credit balance for [userId].
     *
     * The breakdown shows how the balance is composed: carry-over from the
     * previous day (20% rule), carry-over from the 02:00-03:00 window (100%),
     * today's workout earnings, and today's screen time usage.
     *
     * Calls [onResult] with a [CreditBreakdownResult], or a zeroed result on error.
     */
    fun fetchCreditBreakdown(
        userId: String,
        onResult: (CreditBreakdownResult) -> Unit,
    ) {
        scope.launch {
            try {
                val breakdown = get<GetCreditBreakdownUseCase>().invoke(userId)
                val result = if (breakdown != null) {
                    CreditBreakdownResult(
                        availableSeconds = breakdown.availableSeconds,
                        dailyEarnedSeconds = breakdown.dailyEarnedSeconds,
                        dailySpentSeconds = breakdown.dailySpentSeconds,
                        todayWorkoutEarned = breakdown.todayWorkoutEarned,
                        carryOverPercentSeconds = breakdown.carryOverPercentSeconds,
                        carryOverLateNightSeconds = breakdown.carryOverLateNightSeconds,
                        totalEarnedSeconds = breakdown.totalEarnedSeconds,
                        totalSpentSeconds = breakdown.totalSpentSeconds,
                    )
                } else {
                    CreditBreakdownResult(0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L)
                }
                withContext(Dispatchers.Main) { onResult(result) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) {
                    onResult(CreditBreakdownResult(0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L))
                }
            }
        }
    }

    /**
     * Fetches historical daily credit snapshots for [userId] within a date range.
     *
     * Used for building weekly/monthly charts showing earned vs spent over time.
     *
     * @param from ISO-8601 date string (inclusive), e.g. "2026-03-11"
     * @param to ISO-8601 date string (inclusive), e.g. "2026-03-17"
     * @param onResult Callback with the list of snapshots, ordered by date ascending.
     */
    fun fetchCreditHistory(
        userId: String,
        from: String,
        to: String,
        onResult: (List<CreditHistoryEntry>) -> Unit,
    ) {
        scope.launch {
            try {
                val fromDate = LocalDate.parse(from)
                val toDate = LocalDate.parse(to)
                val snapshots = get<DailyCreditSnapshotRepository>()
                    .getByDateRange(userId, fromDate, toDate)
                val entries = snapshots.map { s ->
                    CreditHistoryEntry(
                        date = s.date.toString(),
                        earnedSeconds = s.earnedSeconds,
                        spentSeconds = s.spentSeconds,
                        carryOverSeconds = s.carryOverSeconds,
                        workoutEarnedSeconds = s.workoutEarnedSeconds,
                    )
                }
                withContext(Dispatchers.Main) { onResult(entries) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(emptyList()) }
            }
        }
    }

    /**
     * Fetches daily stats for [userId] on [date] (ISO-8601 string, e.g. "2026-03-09").
     *
     * Calls [onResult] with a [DailyStatsResult] containing the aggregated values,
     * or a zeroed result if no sessions exist for that day.
     */
    fun fetchDailyStats(
        userId: String,
        date: String,
        onResult: (DailyStatsResult) -> Unit,
    ) {
        scope.launch {
            try {
                val localDate = LocalDate.parse(date)
                val stats = get<GetDailyStatsUseCase>().invoke(userId, localDate)
                val result = DailyStatsResult(
                    totalPushUps = stats?.totalPushUps ?: 0,
                    totalSessions = stats?.totalSessions ?: 0,
                    totalEarnedSeconds = stats?.totalEarnedSeconds ?: 0L,
                    averageQuality = stats?.averageQuality?.toDouble() ?: 0.0,
                    averagePushUpsPerSession = stats?.averagePushUpsPerSession?.toDouble() ?: 0.0,
                    bestSession = stats?.bestSession ?: 0,
                )
                withContext(Dispatchers.Main) { onResult(result) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(DailyStatsResult(0, 0, 0L, 0.0, 0.0, 0)) }
            }
        }
    }

    /**
     * Fetches weekly stats for [userId] for the week starting on [weekStart]
     * (ISO-8601 string, e.g. "2026-03-09").
     *
     * Calls [onResult] with a [WeeklyStatsResult].
     */
    fun fetchWeeklyStats(
        userId: String,
        weekStart: String,
        onResult: (WeeklyStatsResult) -> Unit,
    ) {
        scope.launch {
            try {
                val localDate = LocalDate.parse(weekStart)
                val stats = get<GetWeeklyStatsUseCase>().invoke(userId, localDate)
                val dailyList = stats?.dailyBreakdown?.map { day ->
                    DailyStatsResult(
                        totalPushUps = day.totalPushUps,
                        totalSessions = day.totalSessions,
                        totalEarnedSeconds = day.totalEarnedSeconds,
                        averageQuality = day.averageQuality.toDouble(),
                        averagePushUpsPerSession = day.averagePushUpsPerSession.toDouble(),
                        bestSession = day.bestSession,
                    )
                } ?: emptyList()
                val result = WeeklyStatsResult(
                    totalPushUps = stats?.totalPushUps ?: 0,
                    totalSessions = stats?.totalSessions ?: 0,
                    totalEarnedSeconds = stats?.totalEarnedSeconds ?: 0L,
                    averagePushUpsPerSession = stats?.averagePushUpsPerSession?.toDouble() ?: 0.0,
                    bestSession = stats?.bestSession ?: 0,
                    dailyBreakdown = dailyList,
                )
                withContext(Dispatchers.Main) { onResult(result) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(WeeklyStatsResult(0, 0, 0L, 0.0, 0, emptyList())) }
            }
        }
    }

    /**
     * Fetches all-time stats for [userId].
     *
     * Calls [onResult] with a [TotalStatsResult].
     */
    fun fetchTotalStats(
        userId: String,
        onResult: (TotalStatsResult) -> Unit,
    ) {
        scope.launch {
            try {
                val stats = get<GetTotalStatsUseCase>().invoke(userId)
                val result = TotalStatsResult(
                    totalPushUps = stats?.totalPushUps ?: 0,
                    totalSessions = stats?.totalSessions ?: 0,
                    totalEarnedSeconds = stats?.totalEarnedSeconds ?: 0L,
                    totalSpentSeconds = stats?.totalSpentSeconds ?: 0L,
                    averageQuality = stats?.averageQuality?.toDouble() ?: 0.0,
                    averagePushUpsPerSession = stats?.averagePushUpsPerSession?.toDouble() ?: 0.0,
                    bestSession = stats?.bestSession ?: 0,
                    currentStreakDays = stats?.currentStreakDays ?: 0,
                    longestStreakDays = stats?.longestStreakDays ?: 0,
                )
                withContext(Dispatchers.Main) { onResult(result) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(TotalStatsResult(0, 0, 0L, 0L, 0.0, 0.0, 0, 0, 0)) }
            }
        }
    }
}

// =============================================================================
// Plain data transfer objects (no Kotlin generics — safe for Swift export)
// =============================================================================

/** Daily aggregated stats returned by [DataBridge.fetchDailyStats]. */
data class DailyStatsResult(
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageQuality: Double,
    val averagePushUpsPerSession: Double,
    val bestSession: Int,
)

/** Weekly aggregated stats returned by [DataBridge.fetchWeeklyStats]. */
data class WeeklyStatsResult(
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averagePushUpsPerSession: Double,
    val bestSession: Int,
    val dailyBreakdown: List<DailyStatsResult>,
)

/** Single day entry for the credit history chart, returned by [DataBridge.fetchCreditHistory]. */
data class CreditHistoryEntry(
    val date: String,
    val earnedSeconds: Long,
    val spentSeconds: Long,
    val carryOverSeconds: Long,
    val workoutEarnedSeconds: Long,
)

/** Detailed credit breakdown returned by [DataBridge.fetchCreditBreakdown]. */
data class CreditBreakdownResult(
    val availableSeconds: Long,
    val dailyEarnedSeconds: Long,
    val dailySpentSeconds: Long,
    val todayWorkoutEarned: Long,
    val carryOverPercentSeconds: Long,
    val carryOverLateNightSeconds: Long,
    val totalEarnedSeconds: Long,
    val totalSpentSeconds: Long,
)

/** All-time stats returned by [DataBridge.fetchTotalStats]. */
data class TotalStatsResult(
    val totalPushUps: Int,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val totalSpentSeconds: Long,
    val averageQuality: Double,
    val averagePushUpsPerSession: Double,
    val bestSession: Int,
    val currentStreakDays: Int,
    val longestStreakDays: Int,
)
