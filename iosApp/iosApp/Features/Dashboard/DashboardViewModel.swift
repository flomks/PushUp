import SwiftUI

// MARK: - DashboardLoadingState

/// Represents the loading lifecycle for a single data source.
enum DashboardLoadingState {
    case idle
    case loading
    case loaded
    case failed(String)
}

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
    let relativeDate: String  // e.g. "Heute", "Gestern", "vor 3 Tagen"
}

// MARK: - DashboardViewModel

/// Manages all data and state for the Dashboard screen.
///
/// Data is currently simulated with realistic stub values so the UI can be
/// built and previewed without a live backend. Replace the `loadData()`
/// implementation with real KMP use-case calls (GetTimeCreditUseCase,
/// GetDailyStatsUseCase, GetWeeklyStatsUseCase) once the shared module
/// is linked into the iOS target.
@MainActor
final class DashboardViewModel: ObservableObject {

    // MARK: - Published State

    /// Available time credit in seconds.
    @Published private(set) var availableSeconds: Int = 0

    /// Total ever-earned time credit in seconds (used for ring progress).
    @Published private(set) var totalEarnedSeconds: Int = 0

    /// Today's aggregated workout statistics.
    @Published private(set) var dailyStats: DashboardDailyStats? = nil

    /// Per-day push-up counts for the last 7 days (Mon-Sun of current week).
    @Published private(set) var weekDays: [DashboardWeekDay] = []

    /// The most recently completed workout session, if any.
    @Published private(set) var lastSession: DashboardLastSession? = nil

    /// Whether any data has ever been loaded (controls empty-state display).
    @Published private(set) var hasEverWorkedOut: Bool = false

    /// Overall loading state for the initial fetch.
    @Published private(set) var isLoading: Bool = false

    /// Non-nil when a load attempt failed.
    @Published private(set) var errorMessage: String? = nil

    /// Whether a pull-to-refresh is currently in progress.
    @Published private(set) var isRefreshing: Bool = false

    // MARK: - Init

    init() {}

    // MARK: - Actions

    /// Loads all dashboard data. Called on first appear and after pull-to-refresh.
    func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            // Simulate network / database latency
            try await Task.sleep(nanoseconds: 800_000_000)
            applyStubData()
        } catch {
            errorMessage = "Daten konnten nicht geladen werden."
        }

        isLoading = false
    }

    /// Triggered by pull-to-refresh. Reloads all data.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil

        do {
            try await Task.sleep(nanoseconds: 600_000_000)
            applyStubData()
        } catch {
            errorMessage = "Aktualisierung fehlgeschlagen."
        }

        isRefreshing = false
    }

    // MARK: - Private

    /// Populates all published properties with realistic stub data.
    ///
    /// Replace this method body with real KMP use-case invocations:
    /// ```swift
    /// let credit = try await getTimeCreditUseCase(userId: currentUserId)
    /// availableSeconds = Int(credit.availableSeconds)
    /// totalEarnedSeconds = Int(credit.totalEarnedSeconds)
    ///
    /// let today = LocalDate.today()
    /// let daily = try await getDailyStatsUseCase(userId: currentUserId, date: today)
    /// // map daily -> DashboardDailyStats
    ///
    /// let weekly = try await getWeeklyStatsUseCase(userId: currentUserId, weekStartDate: weekStart)
    /// // map weekly.dailyBreakdown -> [DashboardWeekDay]
    /// ```
    private func applyStubData() {
        // Time credit
        availableSeconds  = 5_400   // 1h 30m
        totalEarnedSeconds = 9_000  // 2h 30m

        // Today's stats
        dailyStats = DashboardDailyStats(
            pushUps: 42,
            sessions: 2,
            earnedMinutes: 14,
            averageQuality: 0.84,
            bestSession: 28
        )

        // Weekly bar chart (Mon-Sun, today = index based on weekday)
        let dayLabels = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
        let pushUpValues = [35, 0, 52, 18, 42, 0, 0]
        let todayIndex = todayWeekdayIndex()

        weekDays = dayLabels.enumerated().map { idx, label in
            DashboardWeekDay(
                id: idx,
                label: label,
                pushUps: pushUpValues[idx],
                isToday: idx == todayIndex
            )
        }

        // Last session
        lastSession = DashboardLastSession(
            pushUpCount: 28,
            durationSeconds: 7 * 60 + 23,
            earnedSeconds: 8 * 60 + 24,
            qualityScore: 0.84,
            relativeDate: "Heute"
        )

        hasEverWorkedOut = true
    }

    /// Returns the 0-based weekday index (0 = Monday, 6 = Sunday) for today.
    private func todayWeekdayIndex() -> Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Calendar.weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
        return (weekday + 5) % 7
    }
}
