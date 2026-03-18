import Foundation
import Shared

// MARK: - DashboardDailyStats

/// View-layer model for today's workout statistics.
struct DashboardDailyStats {
    let pushUps: Int
    let sessions: Int
    let earnedMinutes: Int
    let averageQuality: Double
    let bestSession: Int
}

// MARK: - DashboardWeekDay

/// A single day entry for the weekly bar chart.
struct DashboardWeekDay: Identifiable {
    let id: Int          // 0 = Mon ... 6 = Sun
    let label: String    // "Mo", "Di", ...
    let pushUps: Int
    let isToday: Bool
}

// MARK: - DashboardLastSession

/// Compact summary of the most recent completed workout session.
struct DashboardLastSession {
    let pushUpCount: Int
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

    // MARK: - Private

    private var sessionObservationJob: Kotlinx_coroutines_coreJob?
    private var creditObservationJob: Kotlinx_coroutines_coreJob?

    // MARK: - Init

    init() {
        applyEmptyState()
    }

    deinit {
        sessionObservationJob?.cancel(cause: nil)
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
            self.isLoading = false
            self.isRefreshing = false
            self.rebuildDashboard(from: sessions)
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

    /// Rebuilds all dashboard properties from the current list of KMP sessions.
    private func rebuildDashboard(from kmpSessions: [Shared.WorkoutSession]) {
        // Only completed sessions
        let completed = kmpSessions.filter { $0.endedAt != nil }
        hasEverWorkedOut = !completed.isEmpty

        guard !completed.isEmpty else {
            applyEmptyState()
            return
        }

        let calendar = Calendar.current
        let today    = calendar.startOfDay(for: Date())

        // --- Today's stats ---
        let todaySessions = completed.filter { session in
            let startDate = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
            return calendar.startOfDay(for: startDate) == today
        }

        let todayPushUps   = todaySessions.reduce(0) { $0 + Int($1.pushUpCount) }
        let todayEarned    = todaySessions.reduce(0) { $0 + Int($1.earnedTimeCreditSeconds) }
        let todayQuality   = todaySessions.isEmpty ? 0.0
            : todaySessions.reduce(0.0) { $0 + Double($1.quality) } / Double(todaySessions.count)
        let todayBest      = todaySessions.map { Int($0.pushUpCount) }.max() ?? 0

        dailyStats = DashboardDailyStats(
            pushUps: todayPushUps,
            sessions: todaySessions.count,
            earnedMinutes: todayEarned / 60,
            averageQuality: todayQuality,
            bestSession: todayBest
        )

        // --- Weekly chart (Mon–Sun of current week) ---
        let todayIndex = WeekdayHelper.todayIndex()
        let daysFromMonday = todayIndex
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today

        weekDays = WeekdayHelper.dayLabels.enumerated().map { idx, label in
            let dayStart = calendar.date(byAdding: .day, value: idx, to: monday) ?? monday
            let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            let dayPushUps = completed.filter { session in
                let startDate = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
                return startDate >= dayStart && startDate < dayEnd
            }.reduce(0) { $0 + Int($1.pushUpCount) }

            return DashboardWeekDay(
                id: idx,
                label: label,
                pushUps: dayPushUps,
                isToday: idx == todayIndex
            )
        }

        // --- Last session ---
        if let latest = completed.first {
            let startDate = Date(timeIntervalSince1970: Double(latest.startedAt.epochSeconds))
            let endDate   = latest.endedAt.map { Date(timeIntervalSince1970: Double($0.epochSeconds)) }
            let duration  = endDate.map { Int($0.timeIntervalSince(startDate)) } ?? 0

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
                pushUpCount: Int(latest.pushUpCount),
                durationSeconds: duration,
                earnedSeconds: Int(latest.earnedTimeCreditSeconds),
                qualityScore: Double(latest.quality),
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
            DashboardWeekDay(id: idx, label: label, pushUps: 0, isToday: idx == todayIndex)
        }
    }
}
