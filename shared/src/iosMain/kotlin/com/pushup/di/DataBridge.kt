package com.pushup.di

import com.pushup.domain.model.TimeCredit
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.TimeCreditRepository
import com.pushup.domain.repository.WorkoutSessionRepository
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
 * All callbacks are dispatched on [Dispatchers.Main] so Swift ViewModels
 * can update `@Published` properties directly without `DispatchQueue.main.async`.
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

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

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
            .collect { sessions -> onUpdate(sessions) }
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
            .collect { credit -> onUpdate(credit) }
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
                onResult(credit)
            } catch (_: Exception) {
                onResult(null)
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
                onResult(
                    DailyStatsResult(
                        totalPushUps = stats?.totalPushUps ?: 0,
                        totalSessions = stats?.totalSessions ?: 0,
                        totalEarnedSeconds = stats?.totalEarnedSeconds ?: 0L,
                        averageQuality = stats?.averageQuality?.toDouble() ?: 0.0,
                        averagePushUpsPerSession = stats?.averagePushUpsPerSession?.toDouble() ?: 0.0,
                        bestSession = stats?.bestSession ?: 0,
                    )
                )
            } catch (_: Exception) {
                onResult(DailyStatsResult(0, 0, 0L, 0.0, 0.0, 0))
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
                onResult(
                    WeeklyStatsResult(
                        totalPushUps = stats?.totalPushUps ?: 0,
                        totalSessions = stats?.totalSessions ?: 0,
                        totalEarnedSeconds = stats?.totalEarnedSeconds ?: 0L,
                        averagePushUpsPerSession = stats?.averagePushUpsPerSession?.toDouble() ?: 0.0,
                        bestSession = stats?.bestSession ?: 0,
                        dailyBreakdown = dailyList,
                    )
                )
            } catch (_: Exception) {
                onResult(WeeklyStatsResult(0, 0, 0L, 0.0, 0, emptyList()))
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
                onResult(
                    TotalStatsResult(
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
                )
            } catch (_: Exception) {
                onResult(TotalStatsResult(0, 0, 0L, 0L, 0.0, 0.0, 0, 0, 0))
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
