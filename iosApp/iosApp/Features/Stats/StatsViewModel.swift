import Foundation

// MARK: - StatsTab

/// The four time-range tabs available on the Stats screen.
enum StatsTab: Int, CaseIterable, Identifiable {
    case daily   = 0
    case weekly  = 1
    case monthly = 2
    case total   = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .daily:   return "Daily"
        case .weekly:  return "Weekly"
        case .monthly: return "Monthly"
        case .total:   return "Total"
        }
    }
}

// MARK: - DayWorkoutData

/// Represents a single calendar day's workout data.
struct DayWorkoutData: Identifiable {
    let id: String          // "yyyy-MM-dd"
    let date: Date
    let pushUps: Int
    let sessions: Int
    let earnedMinutes: Int
    let averageQuality: Double

    var hasWorkout: Bool { pushUps > 0 }
}

// MARK: - WeeklyBarData

/// A single bar entry for the weekly bar chart.
struct WeeklyBarData: Identifiable {
    let id: Int             // 0 = Mon ... 6 = Sun
    let label: String       // "Mon", "Tue", ...
    let date: Date
    let pushUps: Int
    let sessions: Int
    let earnedMinutes: Int
    let isToday: Bool
}

// MARK: - MonthlyWeekData

/// Aggregated data for one week within a month, used in the line chart.
struct MonthlyWeekData: Identifiable {
    let id: Int             // week index within the month (0-based)
    let label: String       // "W1", "W2", ...
    let weekStart: Date
    let totalPushUps: Int
    let totalSessions: Int
    let totalEarnedMinutes: Int
}

// MARK: - TotalStatsData

/// Lifetime aggregate statistics.
struct TotalStatsData {
    let totalPushUps: Int
    let totalSessions: Int
    let totalEarnedMinutes: Int
    let longestStreakDays: Int
    let currentStreakDays: Int
    let averagePushUpsPerSession: Double
    let averageSessionDurationSeconds: Int
    let bestSingleSession: Int          // push-ups in one session
    let bestDay: Int                    // push-ups in one day
    let bestWeek: Int                   // push-ups in one week
    let activeDays: Int                 // days with at least one workout
    let averageQuality: Double
}

// MARK: - MonthComparison

/// Comparison between the current and previous month.
struct MonthComparison {
    let currentMonthPushUps: Int
    let previousMonthPushUps: Int

    var changePercent: Int {
        guard previousMonthPushUps > 0 else { return 0 }
        let delta = Double(currentMonthPushUps - previousMonthPushUps)
        return Int((delta / Double(previousMonthPushUps)) * 100)
    }

    var isImprovement: Bool { currentMonthPushUps >= previousMonthPushUps }
}

// MARK: - StatsViewModel

/// Manages all data and state for the Stats screen.
///
/// Data is currently simulated with realistic stub values so the UI can be
/// built and previewed without a live backend. Replace the `loadData()`
/// implementation with real KMP use-case calls:
///   - GetDailyStatsUseCase
///   - GetWeeklyStatsUseCase
///   - GetMonthlyStatsUseCase
/// once the shared module is linked into the iOS target.
@MainActor
final class StatsViewModel: ObservableObject {

    // MARK: - Published State

    /// Currently selected time-range tab.
    @Published var selectedTab: StatsTab = .daily

    /// The month currently displayed in the calendar (daily tab).
    @Published var displayedMonth: Date = Date()

    /// The day selected in the calendar for detail view.
    @Published var selectedDay: DayWorkoutData? = nil

    /// Whether the day detail sheet is presented.
    @Published var showDayDetail: Bool = false

    // MARK: Daily

    /// All days in the currently displayed calendar month.
    @Published private(set) var calendarDays: [DayWorkoutData] = []

    // MARK: Weekly

    /// Per-day data for the current week (Mon-Sun).
    @Published private(set) var weeklyBars: [WeeklyBarData] = []

    /// Total push-ups this week.
    @Published private(set) var weeklyTotalPushUps: Int = 0

    /// Average push-ups per active day this week.
    @Published private(set) var weeklyAveragePushUps: Double = 0

    /// Total sessions this week.
    @Published private(set) var weeklyTotalSessions: Int = 0

    /// Total earned minutes this week.
    @Published private(set) var weeklyEarnedMinutes: Int = 0

    // MARK: Monthly

    /// Per-week aggregated data for the current month.
    @Published private(set) var monthlyWeeks: [MonthlyWeekData] = []

    /// Month-over-month comparison.
    @Published private(set) var monthComparison: MonthComparison? = nil

    /// Total push-ups this month.
    @Published private(set) var monthlyTotalPushUps: Int = 0

    /// Total sessions this month.
    @Published private(set) var monthlyTotalSessions: Int = 0

    /// Total earned minutes this month.
    @Published private(set) var monthlyEarnedMinutes: Int = 0

    // MARK: Total

    /// Lifetime aggregate statistics.
    @Published private(set) var totalStats: TotalStatsData? = nil

    // MARK: Loading / Error

    /// Overall loading state for the initial fetch.
    @Published private(set) var isLoading: Bool = false

    /// Whether a pull-to-refresh is currently in progress.
    @Published private(set) var isRefreshing: Bool = false

    /// Non-nil when a load attempt failed.
    @Published var errorMessage: String? = nil

    // MARK: - Init

    init() {}

    // MARK: - Actions

    /// Loads all stats data. Called on first appear.
    func loadData() async {
        guard !isLoading, !isRefreshing else { return }
        isLoading = true
        errorMessage = nil
        await fetchData(errorPrefix: "Failed to load stats.")
        isLoading = false
    }

    /// Triggered by pull-to-refresh.
    func refresh() async {
        guard !isRefreshing, !isLoading else { return }
        isRefreshing = true
        errorMessage = nil
        await fetchData(errorPrefix: "Refresh failed.")
        isRefreshing = false
    }

    /// Clears the current error message.
    func clearError() {
        errorMessage = nil
    }

    /// Navigates to the previous month in the calendar view.
    func previousMonth() {
        displayedMonth = Calendar.current.date(
            byAdding: .month, value: -1, to: displayedMonth
        ) ?? displayedMonth
        Task { await loadCalendarDays() }
    }

    /// Navigates to the next month in the calendar view.
    func nextMonth() {
        displayedMonth = Calendar.current.date(
            byAdding: .month, value: 1, to: displayedMonth
        ) ?? displayedMonth
        Task { await loadCalendarDays() }
    }

    /// Selects a day in the calendar and shows the detail sheet.
    func selectDay(_ day: DayWorkoutData) {
        guard day.hasWorkout else { return }
        selectedDay = day
        showDayDetail = true
    }

    // MARK: - Private

    private func fetchData(errorPrefix: String) async {
        // TODO: Replace with real KMP use-case calls once stats use cases are wired up.
        // For now show empty state — no mock data.
        applyEmptyState()
    }

    private func loadCalendarDays() async {
        // In production: call GetDailyStatsUseCase for the displayed month.
        calendarDays = Self.makeCalendarDays(for: displayedMonth)
    }

    // MARK: - Stub Data

    private func applyEmptyState() {
        calendarDays         = []
        weeklyBars           = Self.makeEmptyWeeklyBars()
        weeklyTotalPushUps   = 0
        weeklyAveragePushUps = 0
        weeklyTotalSessions  = 0
        weeklyEarnedMinutes  = 0
        monthlyWeeks         = []
        monthlyTotalPushUps  = 0
        monthlyTotalSessions = 0
        monthlyEarnedMinutes = 0
        monthComparison      = nil
        totalStats           = nil
    }

    // MARK: - Empty State Factories

    private static func makeCalendarDays(for month: Date) -> [DayWorkoutData] {
        // Returns empty array — real data comes from the backend.
        return []
    }

    private static func makeWeeklyBars() -> [WeeklyBarData] {
        let calendar = Calendar.current
        let today = Date()
        let todayWeekday = calendar.component(.weekday, from: today)
        // Calendar.weekday: 1=Sun, 2=Mon...7=Sat -> 0-based Mon index
        let todayIndex = (todayWeekday + 5) % 7

        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        // Find Monday of current week
        let daysFromMonday = todayIndex
        guard let monday = calendar.date(
            byAdding: .day, value: -daysFromMonday, to: today
        ) else { return [] }

        return labels.enumerated().map { idx, label in
            let date = calendar.date(byAdding: .day, value: idx, to: monday) ?? today
            return WeeklyBarData(
                id: idx,
                label: label,
                date: date,
                pushUps: 0,
                sessions: 0,
                earnedMinutes: 0,
                isToday: idx == todayIndex
            )
        }
    }

    private static func makeEmptyWeeklyBars() -> [WeeklyBarData] {
        return makeWeeklyBars()
    }
}

// MARK: - Formatting Helpers

extension StatsViewModel {

    /// Formats a duration in seconds as "M:SS".
    static func formatDuration(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let m = clamped / 60
        let s = clamped % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: Cached DateFormatters

    /// Cached formatter for "MMMM yyyy" (e.g. "March 2026").
    /// `DateFormatter` is expensive to allocate -- reuse a single instance.
    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    /// Cached formatter for "MMM d" (e.g. "Mar 8").
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    /// Cached formatter for "yyyy-MM-dd" used as calendar day IDs.
    static let dayIdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Returns the display name for a month/year.
    static func monthYearString(for date: Date) -> String {
        monthYearFormatter.string(from: date)
    }

    /// Returns a short date string like "Mar 8".
    static func shortDateString(for date: Date) -> String {
        shortDateFormatter.string(from: date)
    }
}
