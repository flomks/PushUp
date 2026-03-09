import Foundation
import Shared

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

struct WeeklyBarData: Identifiable {
    let id: Int             // 0 = Mon ... 6 = Sun
    let label: String
    let date: Date
    let pushUps: Int
    let sessions: Int
    let earnedMinutes: Int
    let isToday: Bool
}

// MARK: - MonthlyWeekData

struct MonthlyWeekData: Identifiable {
    let id: Int
    let label: String
    let weekStart: Date
    let totalPushUps: Int
    let totalSessions: Int
    let totalEarnedMinutes: Int
}

// MARK: - TotalStatsData

struct TotalStatsData {
    let totalPushUps: Int
    let totalSessions: Int
    let totalEarnedMinutes: Int
    let longestStreakDays: Int
    let currentStreakDays: Int
    let averagePushUpsPerSession: Double
    let averageSessionDurationSeconds: Int
    let bestSingleSession: Int
    let bestDay: Int
    let bestWeek: Int
    let activeDays: Int
    let averageQuality: Double
}

// MARK: - MonthComparison

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
/// Fetches data from the local SQLite database via KMP's `DataBridge`.
/// Data is loaded once on first appear and refreshed on pull-to-refresh.
/// Because the stats use cases aggregate from the local DB, they always
/// reflect the latest completed workouts without requiring a cloud sync.
@MainActor
final class StatsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var selectedTab: StatsTab = .daily
    @Published var displayedMonth: Date = Date()
    @Published var selectedDay: DayWorkoutData? = nil
    @Published var showDayDetail: Bool = false

    // Daily
    @Published private(set) var calendarDays: [DayWorkoutData] = []

    // Weekly
    @Published private(set) var weeklyBars: [WeeklyBarData] = []
    @Published private(set) var weeklyTotalPushUps: Int = 0
    @Published private(set) var weeklyAveragePushUps: Double = 0
    @Published private(set) var weeklyTotalSessions: Int = 0
    @Published private(set) var weeklyEarnedMinutes: Int = 0

    // Monthly
    @Published private(set) var monthlyWeeks: [MonthlyWeekData] = []
    @Published private(set) var monthComparison: MonthComparison? = nil
    @Published private(set) var monthlyTotalPushUps: Int = 0
    @Published private(set) var monthlyTotalSessions: Int = 0
    @Published private(set) var monthlyEarnedMinutes: Int = 0

    // Total
    @Published private(set) var totalStats: TotalStatsData? = nil

    // Loading / Error
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isRefreshing: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Private

    private var currentUserId: String?

    // MARK: - Init

    init() {}

    // MARK: - Actions

    /// Loads all stats data. Called on first appear.
    func loadData() async {
        guard !isLoading, !isRefreshing else { return }
        isLoading = true
        errorMessage = nil
        await fetchAllStats()
        isLoading = false
    }

    /// Triggered by pull-to-refresh.
    func refresh() async {
        guard !isRefreshing, !isLoading else { return }
        isRefreshing = true
        errorMessage = nil
        await fetchAllStats()
        isRefreshing = false
    }

    func clearError() { errorMessage = nil }

    func previousMonth() {
        displayedMonth = Calendar.current.date(
            byAdding: .month, value: -1, to: displayedMonth
        ) ?? displayedMonth
        Task { await loadCalendarDays() }
    }

    func nextMonth() {
        displayedMonth = Calendar.current.date(
            byAdding: .month, value: 1, to: displayedMonth
        ) ?? displayedMonth
        Task { await loadCalendarDays() }
    }

    func selectDay(_ day: DayWorkoutData) {
        guard day.hasWorkout else { return }
        selectedDay = day
        showDayDetail = true
    }

    // MARK: - Private: Fetch

    private func fetchAllStats() async {
        guard let user = await AuthService.shared.getCurrentUser() else {
            applyEmptyState()
            return
        }
        let userId = user.id
        currentUserId = userId

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadWeeklyStats(userId: userId) }
            group.addTask { await self.loadTotalStats(userId: userId) }
            group.addTask { await self.loadCalendarDays() }
        }
    }

    // MARK: - Private: Weekly

    private func loadWeeklyStats(userId: String) async {
        let calendar = Calendar.current
        let today = Date()
        let todayIndex = WeekdayHelper.todayIndex()
        let daysFromMonday = todayIndex
        guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) else { return }

        let isoFormatter = Self.isoDateFormatter
        let weekStartStr = isoFormatter.string(from: monday)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.fetchWeeklyStats(userId: userId, weekStart: weekStartStr) { [weak self] result in
                guard let self else { continuation.resume(); return }
                Task { @MainActor in
                    self.applyWeeklyStats(result: result, monday: monday, todayIndex: todayIndex)
                    continuation.resume()
                }
            }
        }
    }

    private func applyWeeklyStats(result: WeeklyStatsResult, monday: Date, todayIndex: Int) {
        let calendar = Calendar.current
        let labels = WeekdayHelper.dayLabels

        weeklyBars = labels.enumerated().map { idx, label in
            let dayDate = calendar.date(byAdding: .day, value: idx, to: monday) ?? monday
            let daily = idx < result.dailyBreakdown.count ? result.dailyBreakdown[idx] : nil
            return WeeklyBarData(
                id: idx,
                label: label,
                date: dayDate,
                pushUps: Int(daily?.totalPushUps ?? 0),
                sessions: Int(daily?.totalSessions ?? 0),
                earnedMinutes: Int((daily?.totalEarnedSeconds ?? 0) / 60),
                isToday: idx == todayIndex
            )
        }

        weeklyTotalPushUps   = Int(result.totalPushUps)
        weeklyTotalSessions  = Int(result.totalSessions)
        weeklyEarnedMinutes  = Int(result.totalEarnedSeconds / 60)
        weeklyAveragePushUps = result.totalSessions > 0
            ? Double(result.totalPushUps) / Double(result.totalSessions)
            : 0
    }

    // MARK: - Private: Total

    private func loadTotalStats(userId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.fetchTotalStats(userId: userId) { [weak self] result in
                guard let self else { continuation.resume(); return }
                Task { @MainActor in
                    if result.totalSessions > 0 {
                        self.totalStats = TotalStatsData(
                            totalPushUps: Int(result.totalPushUps),
                            totalSessions: Int(result.totalSessions),
                            totalEarnedMinutes: Int(result.totalEarnedSeconds / 60),
                            longestStreakDays: Int(result.longestStreakDays),
                            currentStreakDays: Int(result.currentStreakDays),
                            averagePushUpsPerSession: result.averagePushUpsPerSession,
                            averageSessionDurationSeconds: 0,
                            bestSingleSession: Int(result.bestSession),
                            bestDay: 0,
                            bestWeek: 0,
                            activeDays: 0,
                            averageQuality: result.averageQuality
                        )
                    } else {
                        self.totalStats = nil
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Private: Calendar Days

    private func loadCalendarDays() async {
        guard let userId = currentUserId else {
            calendarDays = []
            return
        }

        let calendar = Calendar.current
        let year  = calendar.component(.year,  from: displayedMonth)
        let month = calendar.component(.month, from: displayedMonth)

        guard let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range    = calendar.range(of: .day, in: .month, for: firstDay) else {
            calendarDays = []
            return
        }

        var days: [DayWorkoutData] = []
        let isoFormatter = Self.isoDateFormatter

        await withTaskGroup(of: DayWorkoutData?.self) { group in
            for day in range {
                guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
                let dateStr = isoFormatter.string(from: date)
                let capturedDate = date

                group.addTask {
                    await withCheckedContinuation { (cont: CheckedContinuation<DayWorkoutData?, Never>) in
                        DataBridge.shared.fetchDailyStats(userId: userId, date: dateStr) { result in
                            let data = DayWorkoutData(
                                id: dateStr,
                                date: capturedDate,
                                pushUps: Int(result.totalPushUps),
                                sessions: Int(result.totalSessions),
                                earnedMinutes: Int(result.totalEarnedSeconds / 60),
                                averageQuality: result.averageQuality
                            )
                            cont.resume(returning: data)
                        }
                    }
                }
            }

            for await result in group {
                if let data = result { days.append(data) }
            }
        }

        calendarDays = days.sorted { $0.date < $1.date }
    }

    // MARK: - Private: Empty State

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

    private static func makeEmptyWeeklyBars() -> [WeeklyBarData] {
        let calendar   = Calendar.current
        let today      = Date()
        let todayIndex = WeekdayHelper.todayIndex()
        let daysFromMonday = todayIndex
        guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) else { return [] }

        return WeekdayHelper.dayLabels.enumerated().map { idx, label in
            let date = calendar.date(byAdding: .day, value: idx, to: monday) ?? today
            return WeeklyBarData(id: idx, label: label, date: date, pushUps: 0, sessions: 0, earnedMinutes: 0, isToday: idx == todayIndex)
        }
    }
}

// MARK: - Formatting Helpers

extension StatsViewModel {

    static func formatDuration(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let m = clamped / 60
        let s = clamped % 60
        return String(format: "%d:%02d", m, s)
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    static let dayIdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func monthYearString(for date: Date) -> String {
        monthYearFormatter.string(from: date)
    }

    static func shortDateString(for date: Date) -> String {
        shortDateFormatter.string(from: date)
    }
}
