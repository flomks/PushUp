import Foundation
import Shared

// MARK: - DashboardDailyStats

/// View-layer model for today's workout statistics.
struct DashboardDailyStats {
    /// Sum of push-ups across today's strength sessions.
    let pushUpCount: Int
    let activeMinutes: Int
    let sessions: Int
    let earnedMinutes: Int
    let averageQuality: Double
}

// MARK: - DashboardWeekDay

/// A single day entry for the weekly bar chart.
struct DashboardWeekDay: Identifiable {
    let id: Int          // 0 = Mon ... 6 = Sun
    let label: String    // "Mo", "Di", ...
    let sessions: Int
    let isToday: Bool
}

// MARK: - DashboardLastSession

/// Compact summary of the most recent completed workout session.
struct DashboardLastSession {
    let primaryMetricValue: String
    let primaryMetricLabel: String
    let primaryMetricIcon: AppIcon
    let durationSeconds: Int
    let earnedSeconds: Int
    let qualityScore: Double
    let relativeDate: String  // e.g. "Today", "Yesterday", "3 days ago"
}

// MARK: - WeekdayHelper

/// Shared helper for Monday-based weekday index calculation.
enum WeekdayHelper {

    static let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static func todayIndex() -> Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return (weekday + 5) % 7
    }
}

// MARK: - DashboardViewModel

/// Manages all data and state for the Dashboard screen.
///
/// Observes the local SQLite database via two KMP Flows:
/// - `DataBridge.observeSessions` — emits on every workout change
/// - `DataBridge.observeTimeCredit` — emits on every credit change
///
/// Both Flows emit immediately with the current value and again whenever
/// the underlying data changes, so the dashboard is always up to date
/// without requiring a manual refresh.
@MainActor
final class DashboardViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var availableSeconds: Int = 0
    @Published private(set) var totalEarnedSeconds: Int = 0
    @Published private(set) var dailyEarnedSeconds: Int = 0
    @Published private(set) var dailySpentSeconds: Int = 0
    @Published private(set) var todayWorkoutEarned: Int = 0
    @Published private(set) var carryOverPercentSeconds: Int = 0
    @Published private(set) var carryOverLateNightSeconds: Int = 0
    @Published private(set) var totalSpentSeconds: Int = 0
    @Published private(set) var dailyStats: DashboardDailyStats? = nil
    @Published private(set) var weekDays: [DashboardWeekDay] = []
    /// Week-over-week change in session count (current calendar week vs previous); `nil` when both weeks are empty.
    @Published private(set) var weekSessionTrendPercent: Int? = nil
    @Published private(set) var lastSession: DashboardLastSession? = nil
    @Published private(set) var hasEverWorkedOut: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var currentUserId: String = ""

    // MARK: - Private

    private var sessionObservationJob: Kotlinx_coroutines_coreJob?
    private var joggingObservationJob: Kotlinx_coroutines_coreJob?
    private var creditObservationJob: Kotlinx_coroutines_coreJob?
    private var pushUpSessions: [Shared.WorkoutSession] = []
    private var joggingSessions: [Shared.JoggingSession] = []

    /// Tracks the last credit value used to configure DeviceActivity monitoring.
    /// Prevents redundant stopMonitoring/startMonitoring system calls when the
    /// credit observer emits the same value multiple times.
    private var lastMonitoredCredit: Int?

    /// The credit value from the previous observer emission. Used to detect
    /// genuine credit increases (new workout) vs stale DB values after login.
    private var lastObservedCredit: Int? = nil

    /// Set to true after the first mismatch reconciliation (isBlocking + positive
    /// credit) in this session. Prevents re-reconciling on subsequent emissions
    /// so that real credit earned from workouts can unblock the apps.
    private var hasReconciledBlockingMismatch: Bool = false

    // MARK: - Init

    init() {
        applyEmptyState()
    }

    deinit {
        sessionObservationJob?.cancel(cause: nil)
        joggingObservationJob?.cancel(cause: nil)
        creditObservationJob?.cancel(cause: nil)
    }

    // MARK: - Actions

    /// Starts observing the local database. Call once on first appear.
    func startObserving() async {
        guard sessionObservationJob == nil else { return }
        isLoading = true

        guard let user = await AuthService.shared.getCurrentUser() else {
            isLoading = false
            applyEmptyState()
            return
        }
        let userId = user.id
        self.currentUserId = userId

        // Observe time credit — updates availableSeconds and totalEarnedSeconds,
        // drives app blocking state, and keeps the DeviceActivity threshold
        // in sync with the current balance.
        creditObservationJob = DataBridge.shared.observeTimeCredit(userId: userId) { [weak self] credit in
            guard let self else { return }
            let available = Int(credit?.availableSeconds ?? 0)

            // Track the previous credit value to detect genuine increases (workouts).
            let previousCredit = self.lastObservedCredit
            self.lastObservedCredit = available

            // Guard each @Published setter so unchanged values don't fire objectWillChange.
            // Each unguarded assignment sends objectWillChange → full DashboardView body re-eval.
            let newTotalEarned = Int(credit?.totalEarnedSeconds ?? 0)
            let newTotalSpent  = Int(credit?.totalSpentSeconds ?? 0)
            let newDailyEarned = Int(credit?.dailyEarnedSeconds ?? 0)
            let newDailySpent  = Int(credit?.dailySpentSeconds ?? 0)
            if self.availableSeconds   != available   { self.availableSeconds   = available }
            if self.totalEarnedSeconds != newTotalEarned { self.totalEarnedSeconds = newTotalEarned }
            if self.totalSpentSeconds  != newTotalSpent  { self.totalSpentSeconds  = newTotalSpent }
            if self.dailyEarnedSeconds != newDailyEarned { self.dailyEarnedSeconds = newDailyEarned }
            if self.dailySpentSeconds  != newDailySpent  { self.dailySpentSeconds  = newDailySpent }

            // Fetch the detailed breakdown (carry-over split, today's workout earned).
            DataBridge.shared.fetchCreditBreakdown(userId: userId) { [weak self] breakdown in
                guard let self else { return }
                let newWorkout   = Int(breakdown.todayWorkoutEarned)
                let newPercent   = Int(breakdown.carryOverPercentSeconds)
                let newLateNight = Int(breakdown.carryOverLateNightSeconds)
                if self.todayWorkoutEarned       != newWorkout   { self.todayWorkoutEarned       = newWorkout }
                if self.carryOverPercentSeconds   != newPercent   { self.carryOverPercentSeconds   = newPercent }
                if self.carryOverLateNightSeconds != newLateNight { self.carryOverLateNightSeconds = newLateNight }
            }

            // Always persist the latest credit to the App Group container so
            // ScreenTimeManager.saveSelection() reads a fresh value when the
            // user adds apps to tracking. Without this, the stored value can
            // be stale (positive from a previous session) even though the
            // actual credit is zero, causing apps to NOT be blocked.
            let sharedDefaults = UserDefaults(suiteName: ScreenTimeConstants.appGroupID)
            sharedDefaults?.set(available, forKey: ScreenTimeConstants.Keys.availableSeconds)

            let screenTime = ScreenTimeManager.shared
            guard screenTime.authorizationStatus == .authorized,
                  screenTime.activitySelection != nil else { return }

            let effectiveCredit = available <= 0 ? 0 : available
            let needsMonitoringRestart = self.lastMonitoredCredit != effectiveCredit

            if available <= 0 {
                // Always call blockApps — it re-applies the shield. Relying on
                // `isBlocking` alone misses the case where memory says blocked but
                // ManagedSettings no longer has an active shield.
                screenTime.blockApps()
                if needsMonitoringRestart {
                    screenTime.stopMonitoring()
                    screenTime.startMonitoring(availableSeconds: 1)
                    self.lastMonitoredCredit = effectiveCredit
                    // startMonitoring writes the sentinel value 1 to App Group, which
                    // would cause reapplyBlockingState() on the next login to wrongly
                    // think credit is available and unblock apps. Restore to 0 so the
                    // persisted credit correctly reflects the exhausted state.
                    sharedDefaults?.set(0, forKey: ScreenTimeConstants.Keys.availableSeconds)
                }
            } else {
                // available > 0 in DB
                if screenTime.isBlocking {
                    // DB shows positive credit but apps are blocked.
                    //
                    // Root cause: SpendTimeCreditUseCase is not called in real-time
                    // as the OS tracks screen time. The DeviceActivity extension
                    // blocks apps when cumulative usage hits the threshold, but the
                    // DB dailySpentSeconds was never incremented. After a logout +
                    // login + cloud sync, the cloud restores the full earned credit,
                    // making the DB show positive credit even though all time was used.
                    //
                    // Fix: if we haven't reconciled yet this session AND this is either
                    // the first emission (previousCredit == nil) or credit didn't
                    // genuinely increase, spend all the remaining DB credit so the
                    // DB reflects reality (0 available). This triggers a new emission
                    // with available = 0, which calls blockApps() and keeps the shield.
                    //
                    // If credit genuinely INCREASED (new workout earned after reconciling),
                    // unblock the apps — the user earned real new time.
                    let creditGenuinelyIncreased = previousCredit != nil && available > previousCredit!
                    if creditGenuinelyIncreased {
                        // New credit from a workout — unblock.
                        screenTime.unblockApps()
                        self.hasReconciledBlockingMismatch = false
                    } else if !self.hasReconciledBlockingMismatch {
                        // Mismatch detected: blocking is active but DB shows credit.
                        // Spend the surplus to reconcile DB with actual usage.
                        self.hasReconciledBlockingMismatch = true
                        DataBridge.shared.spendTimeCredit(
                            userId: userId,
                            seconds: Int64(available)
                        ) { _ in }
                        // Don't unblock or restart monitoring yet — wait for the
                        // next emission (available = 0) triggered by the spend.
                        return
                    }
                    // else: already reconciled this session, keep blocking.
                } else {
                    // Not blocking and has genuine credit — ensure unblocked.
                    // (No-op if already unblocked.)
                }
                if needsMonitoringRestart {
                    screenTime.stopMonitoring()
                    screenTime.startMonitoring(availableSeconds: available)
                    self.lastMonitoredCredit = effectiveCredit
                }
            }
        }

        // Observe sessions — rebuilds daily stats, weekly chart, and last session
        sessionObservationJob = DataBridge.shared.observeSessions(userId: userId) { [weak self] sessions in
            guard let self else { return }
            self.pushUpSessions = sessions
            self.rebuildDashboard()
        }

        // Observe jogging sessions — merge with push-up sessions so dashboard
        // reflects all activity types (not just strength workouts).
        joggingObservationJob = DataBridge.shared.observeJoggingSessions(userId: userId) { [weak self] sessions in
            guard let self else { return }
            self.joggingSessions = sessions
            self.rebuildDashboard()
        }
    }

    /// Pull-to-refresh — data is already live via Flows, just show the indicator briefly.
    func refresh() async {
        guard !isRefreshing, !isLoading else { return }
        isRefreshing = true
        try? await Task.sleep(for: .milliseconds(500))
        isRefreshing = false
    }

    func clearError() { errorMessage = nil }

    // MARK: - Private: Dashboard Computation

    /// Rebuilds all dashboard properties from the current push-up + jogging sessions.
    private func rebuildDashboard() {
        isLoading = false
        isRefreshing = false

        // Only completed sessions
        let completedPushUps = pushUpSessions.filter { $0.endedAt != nil }
        let completedJogging = joggingSessions.filter { $0.endedAt != nil }
        hasEverWorkedOut = !completedPushUps.isEmpty || !completedJogging.isEmpty

        guard hasEverWorkedOut else {
            applyEmptyState()
            return
        }

        let calendar = Calendar.current
        let today    = calendar.startOfDay(for: Date())

        // --- Today's stats ---
        let todayPushUpSessions = completedPushUps.filter { session in
            let startDate = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
            return calendar.startOfDay(for: startDate) == today
        }
        let todayJoggingSessions = completedJogging.filter { session in
            let startDate = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
            return calendar.startOfDay(for: startDate) == today
        }

        let pushUpDuration = todayPushUpSessions.reduce(0) { total, session in
            guard let endedAt = session.endedAt else { return total }
            return total + max(0, Int(endedAt.epochSeconds - session.startedAt.epochSeconds))
        }
        let joggingDuration = todayJoggingSessions.reduce(0) { total, session in
            total + max(0, Int(session.durationSeconds))
        }
        let todayEarned = todayPushUpSessions.reduce(0) { $0 + Int($1.earnedTimeCreditSeconds) }
            + todayJoggingSessions.reduce(0) { $0 + Int($1.earnedTimeCreditSeconds) }
        let todayQuality = todayPushUpSessions.isEmpty ? 0.0
            : todayPushUpSessions.reduce(0.0) { $0 + Double($1.quality) } / Double(todayPushUpSessions.count)
        let pushUpsToday = todayPushUpSessions.reduce(0) { $0 + Int($1.pushUpCount) }

        dailyStats = DashboardDailyStats(
            pushUpCount: pushUpsToday,
            activeMinutes: (pushUpDuration + joggingDuration) / 60,
            sessions: todayPushUpSessions.count + todayJoggingSessions.count,
            earnedMinutes: todayEarned / 60,
            averageQuality: todayQuality
        )

        // --- Weekly chart (Mon–Sun of current week) ---
        let todayIndex = WeekdayHelper.todayIndex()
        let daysFromMonday = todayIndex
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today

        weekDays = WeekdayHelper.dayLabels.enumerated().map { idx, label in
            let dayStart = calendar.date(byAdding: .day, value: idx, to: monday) ?? monday
            let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            let dayPushUpSessions = completedPushUps.filter { session in
                let startDate = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
                return startDate >= dayStart && startDate < dayEnd
            }.count
            let dayJoggingSessions = completedJogging.filter { session in
                let startDate = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
                return startDate >= dayStart && startDate < dayEnd
            }.count

            return DashboardWeekDay(
                id: idx,
                label: label,
                sessions: dayPushUpSessions + dayJoggingSessions,
                isToday: idx == todayIndex
            )
        }

        let thisWeekSessions = weekDays.reduce(0) { $0 + $1.sessions }
        let lastWeekMonday = calendar.date(byAdding: .day, value: -7, to: monday) ?? monday
        var lastWeekSessions = 0
        for idx in 0..<7 {
            let dayStart = calendar.date(byAdding: .day, value: idx, to: lastWeekMonday) ?? lastWeekMonday
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            lastWeekSessions += completedPushUps.filter { session in
                let startDate = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
                return startDate >= dayStart && startDate < dayEnd
            }.count
            lastWeekSessions += completedJogging.filter { session in
                let startDate = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
                return startDate >= dayStart && startDate < dayEnd
            }.count
        }
        if thisWeekSessions == 0 && lastWeekSessions == 0 {
            weekSessionTrendPercent = nil
        } else if lastWeekSessions == 0 {
            weekSessionTrendPercent = thisWeekSessions > 0 ? 100 : 0
        } else {
            weekSessionTrendPercent = Int(
                round(Double(thisWeekSessions - lastWeekSessions) / Double(lastWeekSessions) * 100)
            )
        }

        // --- Last session ---
        let latestPushUp: (date: Date, session: Shared.WorkoutSession)? = completedPushUps
            .compactMap { session in
                let date = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
                return (date: date, session: session)
            }
            .max(by: { $0.date < $1.date })
        let latestJogging: (date: Date, session: Shared.JoggingSession)? = completedJogging
            .compactMap { session in
                let date = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
                return (date: date, session: session)
            }
            .max(by: { $0.date < $1.date })

        if let latest = selectLatestSession(pushUp: latestPushUp, jogging: latestJogging) {
            let startDate = latest.startedAt
            let duration = latest.durationSeconds

            let dayStart = calendar.startOfDay(for: startDate)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            let relativeDate: String
            if dayStart == today {
                relativeDate = "Today"
            } else if dayStart == yesterday {
                relativeDate = "Yesterday"
            } else {
                let days = calendar.dateComponents([.day], from: dayStart, to: today).day ?? 0
                relativeDate = "\(days) days ago"
            }

            lastSession = DashboardLastSession(
                primaryMetricValue: latest.primaryMetricValue,
                primaryMetricLabel: latest.primaryMetricLabel,
                primaryMetricIcon: latest.primaryMetricIcon,
                durationSeconds: duration,
                earnedSeconds: latest.earnedSeconds,
                qualityScore: latest.qualityScore,
                relativeDate: relativeDate
            )
        } else {
            lastSession = nil
        }
    }

    // MARK: - Private: Empty State

    private func applyEmptyState() {
        dailyStats   = nil
        lastSession  = nil
        hasEverWorkedOut = false
        weekSessionTrendPercent = nil

        let todayIndex = WeekdayHelper.todayIndex()
        weekDays = WeekdayHelper.dayLabels.enumerated().map { idx, label in
            DashboardWeekDay(id: idx, label: label, sessions: 0, isToday: idx == todayIndex)
        }
    }

    private struct LastSessionSnapshot {
        let startedAt: Date
        let durationSeconds: Int
        let earnedSeconds: Int
        let qualityScore: Double
        let primaryMetricValue: String
        let primaryMetricLabel: String
        let primaryMetricIcon: AppIcon
    }

    private func selectLatestSession(
        pushUp: (date: Date, session: Shared.WorkoutSession)?,
        jogging: (date: Date, session: Shared.JoggingSession)?
    ) -> LastSessionSnapshot? {
        guard pushUp != nil || jogging != nil else { return nil }

        if let pushUp, let jogging {
            return pushUp.date >= jogging.date
                ? mapPushUpSnapshot(pushUp.session)
                : mapJoggingSnapshot(jogging.session)
        }
        if let pushUp {
            return mapPushUpSnapshot(pushUp.session)
        }
        if let jogging {
            return mapJoggingSnapshot(jogging.session)
        }
        return nil
    }

    private func mapPushUpSnapshot(_ session: Shared.WorkoutSession) -> LastSessionSnapshot {
        let duration: Int = {
            guard let endedAt = session.endedAt else { return 0 }
            return max(0, Int(endedAt.epochSeconds - session.startedAt.epochSeconds))
        }()

        return LastSessionSnapshot(
            startedAt: Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds)),
            durationSeconds: duration,
            earnedSeconds: Int(session.earnedTimeCreditSeconds),
            qualityScore: Double(session.quality),
            primaryMetricValue: "\(session.pushUpCount)",
            primaryMetricLabel: "Push-Ups",
            primaryMetricIcon: .figureStrengthTraining
        )
    }

    private func mapJoggingSnapshot(_ session: Shared.JoggingSession) -> LastSessionSnapshot {
        let distanceLabel: String = {
            if session.distanceMeters >= 1000 {
                return String(format: "%.2f km", session.distanceMeters / 1000.0)
            }
            return "\(Int(session.distanceMeters)) m"
        }()

        return LastSessionSnapshot(
            startedAt: Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds)),
            durationSeconds: Int(session.durationSeconds),
            earnedSeconds: Int(session.earnedTimeCreditSeconds),
            qualityScore: 0.0,
            primaryMetricValue: distanceLabel,
            primaryMetricLabel: "Distance",
            primaryMetricIcon: .figureRun
        )
    }
}
