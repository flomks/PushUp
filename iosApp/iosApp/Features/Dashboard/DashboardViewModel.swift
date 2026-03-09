import Foundation

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
/// Avoids duplicating the Calendar.weekday -> 0-based Monday index
/// conversion across ViewModel and chart components.
enum WeekdayHelper {

    /// Day labels for the English locale, Monday through Sunday.
    static let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Returns the 0-based weekday index (0 = Monday, 6 = Sunday) for today.
    static func todayIndex() -> Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Calendar.weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
        return (weekday + 5) % 7
    }
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
    @Published var errorMessage: String? = nil

    /// Whether a pull-to-refresh is currently in progress.
    @Published private(set) var isRefreshing: Bool = false

    // MARK: - Init

    init() {}

    // MARK: - Actions

    /// Loads all dashboard data. Called on first appear.
    /// Skips if already loading or refreshing to prevent concurrent fetches.
    func loadData() async {
        guard !isLoading, !isRefreshing else { return }
        isLoading = true
        errorMessage = nil

        await fetchData(errorPrefix: "Failed to load data.")

        isLoading = false
    }

    /// Triggered by pull-to-refresh. Reloads all data.
    /// Skips if already loading or refreshing to prevent concurrent fetches.
    func refresh() async {
        guard !isRefreshing, !isLoading else { return }
        isRefreshing = true
        errorMessage = nil

        await fetchData(errorPrefix: "Refresh failed.")

        isRefreshing = false
    }

    /// Clears the current error message. Called when the user dismisses
    /// the error alert.
    func clearError() {
        errorMessage = nil
    }

    // MARK: - Private

    /// Shared fetch logic used by both `loadData()` and `refresh()`.
    private func fetchData(errorPrefix: String) async {
        do {
            // TODO: Replace with real KMP use-case calls once
            // GetTimeCreditUseCase / GetDailyStatsUseCase are wired up.
            // For now show an empty state — no mock data.
            applyEmptyState()
        } catch is CancellationError {
            // Task was cancelled (e.g. view disappeared) -- do not set error.
        } catch {
            errorMessage = errorPrefix
        }
    }

    /// Resets all published properties to their empty/zero state.
    /// Shown until real data is loaded from the backend.
    private func applyEmptyState() {
        availableSeconds   = 0
        totalEarnedSeconds = 0
        dailyStats         = nil
        lastSession        = nil
        hasEverWorkedOut   = false

        let todayIndex = WeekdayHelper.todayIndex()
        weekDays = WeekdayHelper.dayLabels.enumerated().map { idx, label in
            DashboardWeekDay(
                id: idx,
                label: label,
                pushUps: 0,
                isToday: idx == todayIndex
            )
        }
    }
}
