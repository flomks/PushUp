package com.pushup.di

import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.JoggingSegment
import com.pushup.domain.model.LiveRunSessionState
import com.pushup.domain.model.RunMode
import com.pushup.domain.model.RunPresenceState
import com.pushup.domain.model.RunVisibility
import com.pushup.domain.model.PushUpRecord
import com.pushup.domain.model.RoutePoint
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.LiveRunPresenceRepository
import com.pushup.domain.repository.LiveRunSessionRepository
import com.pushup.domain.repository.RunEventRepository
import com.pushup.domain.repository.DailyCreditSnapshotRepository
import com.pushup.domain.repository.JoggingSessionRepository
import com.pushup.domain.repository.PushUpRecordRepository
import com.pushup.domain.repository.RoutePointRepository
import com.pushup.domain.repository.RunXpAwardRepository
import com.pushup.domain.repository.TimeCreditRepository
import com.pushup.domain.repository.UserSettingsRepository
import com.pushup.domain.repository.WorkoutSessionRepository
import com.pushup.db.PushUpDatabase
import com.pushup.domain.usecase.CreateRunEventUseCase
import com.pushup.domain.usecase.GetCreditBreakdownUseCase
import com.pushup.domain.usecase.GetDailyStatsUseCase
import com.pushup.domain.usecase.GetJoggingSegmentsUseCase
import com.pushup.domain.usecase.GetTimeCreditUseCase
import com.pushup.domain.usecase.GetTotalStatsUseCase
import com.pushup.domain.usecase.GetUpcomingRunEventsUseCase
import com.pushup.domain.usecase.GetWeeklyStatsUseCase
import com.pushup.domain.usecase.GetUserSettingsUseCase
import com.pushup.domain.usecase.FinishLiveRunSessionUseCase
import com.pushup.domain.usecase.JoinLiveRunSessionUseCase
import com.pushup.domain.usecase.LeaveLiveRunSessionUseCase
import com.pushup.domain.usecase.ObserveFriendsActiveRunsUseCase
import com.pushup.domain.usecase.ObserveLiveRunSessionUseCase
import com.pushup.domain.usecase.RespondToRunEventUseCase
import com.pushup.domain.usecase.StartLiveRunSessionUseCase
import com.pushup.domain.usecase.UpdateLiveRunPresenceUseCase
import com.pushup.domain.usecase.UpdateUserSettingsUseCase
import com.pushup.domain.usecase.ApplyDailyResetUseCase
import com.pushup.domain.usecase.SpendTimeCreditUseCase
import com.pushup.domain.usecase.SpendResult
import com.pushup.domain.usecase.sync.UserSettingsDashboardSyncUseCase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.datetime.Instant
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

    private fun parseRunMode(raw: String): RunMode =
        runCatching { RunMode.valueOf(raw.trim().uppercase()) }.getOrDefault(RunMode.BASE)

    private fun parseRunVisibility(raw: String): RunVisibility =
        runCatching { RunVisibility.valueOf(raw.trim().uppercase()) }.getOrDefault(RunVisibility.FRIENDS)

    private fun parseRunPresenceState(raw: String): RunPresenceState =
        runCatching { RunPresenceState.valueOf(raw.trim().uppercase()) }.getOrDefault(RunPresenceState.ACTIVE)

    private fun toRunEventResult(
        event: com.pushup.domain.model.RunEvent,
        participantCount: Int = 0,
        currentUserStatus: String? = null,
    ): RunEventResult = RunEventResult(
        id = event.id,
        title = event.title,
        mode = event.mode.name,
        visibility = event.visibility.name,
        status = event.status.name,
        plannedStartAt = event.plannedStartAt.toString(),
        plannedEndAt = event.plannedEndAt?.toString(),
        locationName = event.locationName,
        participantCount = participantCount,
        currentUserStatus = currentUserStatus,
    )

    private fun toLiveRunSessionResult(
        session: com.pushup.domain.model.LiveRunSession,
        participantCount: Int = 0,
    ): LiveRunSessionResult = LiveRunSessionResult(
        id = session.id,
        linkedEventId = session.linkedEventId,
        leaderUserId = session.leaderUserId,
        mode = session.mode.name,
        visibility = session.visibility.name,
        state = session.state.name,
        startedAt = session.startedAt.toString(),
        participantCount = participantCount,
    )

    private fun toLiveRunParticipantResult(
        participant: com.pushup.domain.model.LiveRunParticipant,
    ): LiveRunParticipantResult = LiveRunParticipantResult(
        id = participant.id,
        userId = participant.userId,
        status = participant.status.name,
        isLeader = participant.isLeader,
    )

    private fun toRunXpAwardResult(
        award: com.pushup.domain.model.RunXpAward,
    ): RunXpAwardResult = RunXpAwardResult(
        id = award.id,
        userId = award.userId,
        sessionId = award.sessionId,
        baseXp = award.baseXp,
        bonusType = award.bonusType.name,
        bonusMultiplier = award.bonusMultiplier,
        bonusXp = award.bonusXp,
        totalXpAwarded = award.totalXpAwarded,
        awardedAt = award.awardedAt.toString(),
    )

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
    // Social running
    // =========================================================================

    fun fetchUpcomingRunEvents(
        userId: String,
        onResult: (List<RunEventResult>) -> Unit,
    ) {
        scope.launch {
            try {
                val repository = get<RunEventRepository>()
                val events = get<GetUpcomingRunEventsUseCase>().invoke(userId)
                val results = events.map { event ->
                    val participants = repository.getParticipants(event.id)
                    toRunEventResult(
                        event = event,
                        participantCount = participants.size,
                        currentUserStatus = participants.firstOrNull { it.userId == userId }?.status?.name,
                    )
                }
                withContext(Dispatchers.Main) { onResult(results) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(emptyList()) }
            }
        }
    }

    fun fetchFriendsActiveRuns(
        userId: String,
        onResult: (List<LiveRunSessionResult>) -> Unit,
    ) {
        scope.launch {
            try {
                val repository = get<LiveRunSessionRepository>()
                val sessions = get<ObserveFriendsActiveRunsUseCase>().invoke(userId)
                    .filter { it.state != LiveRunSessionState.FINISHED }
                val results = sessions.map { session ->
                    toLiveRunSessionResult(
                        session = session,
                        participantCount = repository.getParticipants(session.id).size,
                    )
                }
                withContext(Dispatchers.Main) { onResult(results) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(emptyList()) }
            }
        }
    }

    fun observeLiveRunSession(
        sessionId: String,
        onUpdate: (LiveRunSessionSnapshotResult) -> Unit,
    ): Job = scope.launch {
        get<ObserveLiveRunSessionUseCase>()
            .invoke(sessionId)
            .catch { /* best-effort live updates */ }
            .collect { snapshot ->
                val result = LiveRunSessionSnapshotResult(
                    session = snapshot.session?.let { session ->
                        toLiveRunSessionResult(
                            session = session,
                            participantCount = snapshot.participants.size,
                        )
                    },
                    participants = snapshot.participants.map(::toLiveRunParticipantResult),
                    presenceCount = snapshot.presenceCount,
                )
                withContext(Dispatchers.Main) { onUpdate(result) }
            }
    }

    fun fetchLiveRunSessionSnapshot(
        sessionId: String,
        onResult: (LiveRunSessionSnapshotResult?) -> Unit,
    ) {
        scope.launch {
            try {
                val sessionRepository = get<LiveRunSessionRepository>()
                val presenceRepository = get<LiveRunPresenceRepository>()
                val session = sessionRepository.getById(sessionId)
                val participants = sessionRepository.getParticipants(sessionId)
                val result = LiveRunSessionSnapshotResult(
                    session = session?.let {
                        toLiveRunSessionResult(
                            session = it,
                            participantCount = participants.size,
                        )
                    },
                    participants = participants.map(::toLiveRunParticipantResult),
                    presenceCount = presenceRepository.getForSession(sessionId).size,
                )
                withContext(Dispatchers.Main) { onResult(result) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(null) }
            }
        }
    }

    fun startLiveRunSession(
        leaderUserId: String,
        mode: String,
        visibility: String,
        linkedEventId: String?,
        onResult: (LiveRunSessionResult?) -> Unit,
    ) {
        scope.launch {
            try {
                val session = get<StartLiveRunSessionUseCase>().invoke(
                    leaderUserId = leaderUserId,
                    mode = parseRunMode(mode),
                    visibility = parseRunVisibility(visibility),
                    linkedEventId = linkedEventId,
                )
                val participantCount = get<LiveRunSessionRepository>().getParticipants(session.id).size
                withContext(Dispatchers.Main) {
                    onResult(toLiveRunSessionResult(session, participantCount))
                }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(null) }
            }
        }
    }

    fun joinLiveRunSession(
        sessionId: String,
        userId: String,
        onResult: (Boolean) -> Unit,
    ) {
        scope.launch {
            val ok = runCatching {
                get<JoinLiveRunSessionUseCase>().invoke(sessionId, userId)
            }.isSuccess
            withContext(Dispatchers.Main) { onResult(ok) }
        }
    }

    fun inviteUserToLiveRunSession(
        sessionId: String,
        userId: String,
        onResult: (Boolean) -> Unit,
    ) {
        scope.launch {
            val ok = runCatching {
                val repository = get<LiveRunSessionRepository>()
                repository.getById(sessionId) ?: error("Live run session not found: $sessionId")
                val now = Instant.fromEpochMilliseconds(kotlinx.datetime.Clock.System.now().toEpochMilliseconds())
                val existing = repository.getParticipants(sessionId).firstOrNull { it.userId == userId }
                repository.upsertParticipant(
                    existing?.copy(
                        status = com.pushup.domain.model.RunParticipantStatus.INVITED,
                        leftAt = null,
                        finishedAt = null,
                        updatedAt = now,
                    ) ?: com.pushup.domain.model.LiveRunParticipant(
                        id = "invite_${sessionId}_${userId}_${now.toEpochMilliseconds()}",
                        sessionId = sessionId,
                        userId = userId,
                        status = com.pushup.domain.model.RunParticipantStatus.INVITED,
                        joinedAt = now,
                        becameActiveAt = null,
                        finishedAt = null,
                        leftAt = null,
                        isLeader = false,
                        createdAt = now,
                        updatedAt = now,
                    )
                )
            }.isSuccess
            withContext(Dispatchers.Main) { onResult(ok) }
        }
    }

    fun leaveLiveRunSession(
        sessionId: String,
        userId: String,
        onResult: (Boolean) -> Unit,
    ) {
        scope.launch {
            val ok = runCatching {
                get<LeaveLiveRunSessionUseCase>().invoke(sessionId, userId)
            }.isSuccess
            withContext(Dispatchers.Main) { onResult(ok) }
        }
    }

    fun finishLiveRunSession(
        sessionId: String,
        userId: String,
        onResult: (Boolean) -> Unit,
    ) {
        scope.launch {
            val ok = runCatching {
                get<FinishLiveRunSessionUseCase>().invoke(sessionId, userId)
            }.isSuccess
            withContext(Dispatchers.Main) { onResult(ok) }
        }
    }

    fun updateLiveRunPresence(
        sessionId: String,
        userId: String,
        state: String,
        distanceMeters: Double,
        durationSeconds: Long,
        paceSecondsPerKm: Int?,
        latitude: Double?,
        longitude: Double?,
        onDone: (Boolean) -> Unit,
    ) {
        scope.launch {
            val ok = runCatching {
                get<UpdateLiveRunPresenceUseCase>().invoke(
                    sessionId = sessionId,
                    userId = userId,
                    state = parseRunPresenceState(state),
                    distanceMeters = distanceMeters,
                    durationSeconds = durationSeconds,
                    paceSecondsPerKm = paceSecondsPerKm,
                    latitude = latitude,
                    longitude = longitude,
                )
            }.isSuccess
            withContext(Dispatchers.Main) { onDone(ok) }
        }
    }

    fun createRunEvent(
        organizerUserId: String,
        title: String,
        mode: String,
        visibility: String,
        plannedStartAt: String,
        invitedUserIds: List<String>,
        description: String?,
        plannedEndAt: String?,
        locationName: String?,
        onResult: (RunEventResult?) -> Unit,
    ) {
        scope.launch {
            try {
                val event = get<CreateRunEventUseCase>().invoke(
                    organizerUserId = organizerUserId,
                    title = title,
                    mode = parseRunMode(mode),
                    visibility = parseRunVisibility(visibility),
                    plannedStartAt = Instant.parse(plannedStartAt),
                    invitedUserIds = invitedUserIds,
                    description = description,
                    plannedEndAt = plannedEndAt?.let(Instant::parse),
                    locationName = locationName,
                )
                val participantCount = get<RunEventRepository>().getParticipants(event.id).size
                withContext(Dispatchers.Main) { onResult(toRunEventResult(event, participantCount)) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(null) }
            }
        }
    }

    fun respondToRunEvent(
        eventId: String,
        userId: String,
        status: String,
        onDone: (Boolean) -> Unit,
    ) {
        scope.launch {
            val ok = runCatching {
                val normalized = status.trim().uppercase()
                get<RespondToRunEventUseCase>().invoke(
                    eventId = eventId,
                    userId = userId,
                    accept = normalized != "DECLINED",
                )
            }.isSuccess
            withContext(Dispatchers.Main) { onDone(ok) }
        }
    }

    fun checkInRunEvent(
        eventId: String,
        userId: String,
        onDone: (Boolean) -> Unit,
    ) {
        scope.launch {
            val ok = runCatching {
                get<RunEventRepository>().updateParticipantStatus(
                    eventId = eventId,
                    userId = userId,
                    status = com.pushup.domain.model.RunParticipantStatus.CHECKED_IN,
                )
            }.isSuccess
            withContext(Dispatchers.Main) { onDone(ok) }
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

    /**
     * Fetches all pause/run timeline segments for a jogging [sessionId].
     */
    fun fetchJoggingSegmentsForSession(
        sessionId: String,
        onResult: (List<JoggingSegment>) -> Unit,
    ) {
        scope.launch {
            try {
                val segments = get<GetJoggingSegmentsUseCase>().invoke(sessionId)
                withContext(Dispatchers.Main) { onResult(segments) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(emptyList()) }
            }
        }
    }

    fun fetchJoggingSession(
        sessionId: String,
        onResult: (JoggingSession?) -> Unit,
    ) {
        scope.launch {
            try {
                val session = get<JoggingSessionRepository>().getById(sessionId)
                withContext(Dispatchers.Main) { onResult(session) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(null) }
            }
        }
    }

    fun fetchRunXpAwardsForSession(
        sessionId: String,
        onResult: (List<RunXpAwardResult>) -> Unit,
    ) {
        scope.launch {
            try {
                val awards = get<RunXpAwardRepository>()
                    .getBySessionId(sessionId)
                    .map(::toRunXpAwardResult)
                withContext(Dispatchers.Main) { onResult(awards) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(emptyList()) }
            }
        }
    }

    fun fetchRunUsers(
        userIds: List<String>,
        onResult: (List<RunUserSummaryResult>) -> Unit,
    ) {
        scope.launch {
            try {
                val queries = get<PushUpDatabase>().databaseQueries
                val users = userIds
                    .distinct()
                    .mapNotNull { userId ->
                        queries.selectUserById(userId).executeAsOneOrNull()?.let { user ->
                            RunUserSummaryResult(
                                id = user.id,
                                username = user.username,
                                displayName = user.displayName,
                                avatarUrl = user.avatarUrl,
                            )
                        }
                    }
                withContext(Dispatchers.Main) { onResult(users) }
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
        // Ensure a due daily reset is applied before the observer starts emitting.
        // This avoids showing stale credit values when the app opens after days offline.
        runCatching { get<ApplyDailyResetUseCase>().invoke(userId) }

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
     * Spends (deducts) [seconds] from the user's credit balance.
     *
     * Called when the DeviceActivity extension has blocked apps but the local
     * DB still shows a positive balance — because [SpendTimeCreditUseCase] is
     * not called in real-time as screen time is consumed. This reconciles the
     * DB so it accurately reflects 0 remaining credit, ensuring that after a
     * logout + login + cloud sync the correct (zero) balance is restored.
     *
     * Calls [onResult] with `true` on success, `false` if the balance is
     * already 0, there are insufficient credits, or an error occurs.
     */
    fun spendTimeCredit(
        userId: String,
        seconds: Long,
        onResult: (Boolean) -> Unit,
    ) {
        if (seconds <= 0L) {
            scope.launch { withContext(Dispatchers.Main) { onResult(false) } }
            return
        }
        scope.launch {
            try {
                val result = get<SpendTimeCreditUseCase>().invoke(userId, seconds)
                val success = result is SpendResult.Success
                withContext(Dispatchers.Main) { onResult(success) }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) { onResult(false) }
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

    // =========================================================================
    // Dashboard widget order (mirrors Supabase user_settings.dashboard_widget_order_json)
    // =========================================================================

    /**
     * Emits whenever [com.pushup.domain.model.UserSettings.dashboardWidgetOrderJson] changes locally.
     */
    fun observeDashboardWidgetOrderJson(
        userId: String,
        onUpdate: (String?) -> Unit,
    ): Job = scope.launch {
        get<UserSettingsRepository>()
            .observeSettings(userId)
            .map { settings -> settings?.dashboardWidgetOrderJson }
            .distinctUntilChanged()
            .catch { /* best-effort live updates */ }
            .collect { json ->
                withContext(Dispatchers.Main) { onUpdate(json) }
            }
    }

    /**
     * Persists [json] into local UserSettings and PATCHes Supabase (when online).
     */
    fun saveDashboardWidgetOrderJson(
        userId: String,
        json: String,
        onDone: (Boolean) -> Unit,
    ) {
        scope.launch {
            val ok = runCatching {
                val getSettings = get<GetUserSettingsUseCase>()
                val updateSettings = get<UpdateUserSettingsUseCase>()
                val dashboardSync = get<UserSettingsDashboardSyncUseCase>()
                val current = getSettings(userId)
                updateSettings(current.copy(dashboardWidgetOrderJson = json))
                dashboardSync.pushToRemote(userId)
            }.isSuccess
            withContext(Dispatchers.Main) { onDone(ok) }
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

data class RunEventResult(
    val id: String,
    val title: String,
    val mode: String,
    val visibility: String,
    val status: String,
    val plannedStartAt: String,
    val plannedEndAt: String?,
    val locationName: String?,
    val participantCount: Int,
    val currentUserStatus: String?,
)

data class LiveRunSessionResult(
    val id: String,
    val linkedEventId: String?,
    val leaderUserId: String,
    val mode: String,
    val visibility: String,
    val state: String,
    val startedAt: String,
    val participantCount: Int,
)

data class LiveRunParticipantResult(
    val id: String,
    val userId: String,
    val status: String,
    val isLeader: Boolean,
)

data class LiveRunSessionSnapshotResult(
    val session: LiveRunSessionResult?,
    val participants: List<LiveRunParticipantResult>,
    val presenceCount: Int,
)

data class RunXpAwardResult(
    val id: String,
    val userId: String,
    val sessionId: String,
    val baseXp: Long,
    val bonusType: String,
    val bonusMultiplier: Double,
    val bonusXp: Long,
    val totalXpAwarded: Long,
    val awardedAt: String,
)

data class RunUserSummaryResult(
    val id: String,
    val username: String?,
    val displayName: String,
    val avatarUrl: String?,
)
