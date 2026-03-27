import Foundation
import Shared

// MARK: - DashboardDailyStats

/// View-layer model for today's workout statistics.
struct DashboardDailyStats {
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
            self.availableSeconds    = available
            self.totalEarnedSeconds  = Int(credit?.totalEarnedSeconds ?? 0)
            self.totalSpentSeconds   = Int(credit?.totalSpentSeconds ?? 0)
            self.dailyEarnedSeconds  = Int(credit?.dailyEarnedSeconds ?? 0)
            self.dailySpentSeconds   = Int(credit?.dailySpentSeconds ?? 0)

            // Fetch the detailed breakdown (carry-over split, today's workout earned).
            DataBridge.shared.fetchCreditBreakdown(userId: userId) { [weak self] breakdown in
                guard let self else { return }
                self.todayWorkoutEarned        = Int(breakdown.todayWorkoutEarned)
                self.carryOverPercentSeconds    = Int(breakdown.carryOverPercentSeconds)
                self.carryOverLateNightSeconds  = Int(breakdown.carryOverLateNightSeconds)
            }

            let screenTime = ScreenTimeManager.shared
            guard screenTime.authorizationStatus == .authorized,
                  screenTime.activitySelection != nil else { return }

            if available <= 0 {
                // Credit exhausted — activate the shield immediately.
                if !screenTime.isBlocking {
                    screenTime.blockApps()
                }
                // Keep DeviceActivity monitoring running even at 0 credit.
                // This is critical for two reasons:
                //   1. The extension tracks real usage so todaySystemUsageSeconds
                //      stays accurate for the usage display.
                //   2. When the user earns new credit via a workout, monitoring
                //      is restarted with the new threshold. If we stopped it here
                //      the extension would never write usage data.
                // Use threshold = 1 second so the event fires immediately and
                // the extension records the current usage snapshot.
                screenTime.stopMonitoring()
                screenTime.startMonitoring(availableSeconds: 1)
            } else {
                // Credit is positive — ensure apps are unblocked and the
                // DeviceActivity threshold is set to the current balance so
                // the system blocks automatically when the user exhausts it.
                if screenTime.isBlocking {
                    screenTime.unblockApps()
                }
                // Always restart monitoring with the fresh threshold.
                // stopMonitoring() first so startMonitoring() can register
                // the updated threshold (DeviceActivityCenter throws if the
                // same activity name is already being monitored).
                screenTime.stopMonitoring()
                screenTime.startMonitoring(availableSeconds: available)
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

        dailyStats = DashboardDailyStats(
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
