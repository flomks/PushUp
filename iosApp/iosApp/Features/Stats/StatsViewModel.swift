import Foundation
import Shared

// MARK: - StatsTab

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
    let id: Int
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
/// Observes the local SQLite database via `DataBridge.observeSessions`.
/// All stats are computed in-memory from the session list, which is instant.
/// No per-day API calls are made -- the Flow emits the full session list and
/// this ViewModel aggregates it into daily/weekly/monthly/total views.
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

    private var allSessions: [Shared.WorkoutSession] = []
    private var observationJob: Kotlinx_coroutines_coreJob?

    // MARK: - Init / Deinit

    init() {}

    deinit {
        observationJob?.cancel(cause: nil)
    }

    // MARK: - Actions

    func loadData() async {
        guard observationJob == nil else { return }
        isLoading = true
        errorMessage = nil

        guard let user = await AuthService.shared.getCurrentUser() else {
            isLoading = false
            applyEmptyState()
            return
        }

        observationJob = DataBridge.shared.observeSessions(userId: user.id) { [weak self] sessions in
            guard let self else { return }
            self.allSessions = sessions.filter { $0.endedAt != nil }
            self.rebuildAllStats()
            self.isLoading = false
            self.isRefreshing = false
        }
    }

    func refresh() async {
        guard !isRefreshing, !isLoading else { return }
        isRefreshing = true
        try? await Task.sleep(for: .milliseconds(500))
        isRefreshing = false
    }

    func clearError() { errorMessage = nil }

    func previousMonth() {
        displayedMonth = Calendar.current.date(
            byAdding: .month, value: -1, to: displayedMonth
        ) ?? displayedMonth
        rebuildCalendarDays()
        rebuildMonthlyStats()
    }

    func nextMonth() {
        displayedMonth = Calendar.current.date(
            byAdding: .month, value: 1, to: displayedMonth
        ) ?? displayedMonth
        rebuildCalendarDays()
        rebuildMonthlyStats()
    }

    func selectDay(_ day: DayWorkoutData) {
        guard day.hasWorkout else { return }
        selectedDay = day
        showDayDetail = true
    }

    // MARK: - Private: Rebuild All

    private func rebuildAllStats() {
        rebuildCalendarDays()
        rebuildWeeklyStats()
        rebuildMonthlyStats()
        rebuildTotalStats()
    }

    // MARK: - Private: Calendar Days

    private func rebuildCalendarDays() {
        let calendar = Calendar.current
        let year  = calendar.component(.year,  from: displayedMonth)
        let month = calendar.component(.month, from: displayedMonth)

        guard let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range    = calendar.range(of: .day, in: .month, for: firstDay) else {
            calendarDays = []
            return
        }

        let sessionsByDay = groupSessionsByDayKey(allSessions)

        calendarDays = range.compactMap { day -> DayWorkoutData? in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            let key = Self.isoDateFormatter.string(from: date)
            let daySessions = sessionsByDay[key] ?? []
            let pushUps = daySessions.reduce(0) { $0 + Int($1.pushUpCount) }
            let earned  = daySessions.reduce(0) { $0 + Int($1.earnedTimeCreditSeconds) }
            let quality = daySessions.isEmpty ? 0.0
                : daySessions.reduce(0.0) { $0 + Double($1.quality) } / Double(daySessions.count)
            return DayWorkoutData(
                id: key, date: date, pushUps: pushUps,
                sessions: daySessions.count, earnedMinutes: earned / 60,
                averageQuality: quality
            )
        }
    }

    // MARK: - Private: Weekly Stats

    private func rebuildWeeklyStats() {
        let calendar = Calendar.current
        let today = Date()
        let todayIndex = WeekdayHelper.todayIndex()
        guard let monday = calendar.date(byAdding: .day, value: -todayIndex, to: calendar.startOfDay(for: today)) else {
            weeklyBars = Self.makeEmptyWeeklyBars()
            return
        }

        let sessionsByDay = groupSessionsByDayKey(allSessions)
        var totalPU = 0, totalSess = 0, totalEarned = 0

        weeklyBars = WeekdayHelper.dayLabels.enumerated().map { idx, label in
            let dayDate = calendar.date(byAdding: .day, value: idx, to: monday) ?? monday
            let key = Self.isoDateFormatter.string(from: dayDate)
            let daySessions = sessionsByDay[key] ?? []
            let pu = daySessions.reduce(0) { $0 + Int($1.pushUpCount) }
            let earned = daySessions.reduce(0) { $0 + Int($1.earnedTimeCreditSeconds) }
            totalPU += pu
            totalSess += daySessions.count
            totalEarned += earned
            return WeeklyBarData(
                id: idx, label: label, date: dayDate,
                pushUps: pu, sessions: daySessions.count,
                earnedMinutes: earned / 60, isToday: idx == todayIndex
            )
        }

        weeklyTotalPushUps   = totalPU
        weeklyTotalSessions  = totalSess
        weeklyEarnedMinutes  = totalEarned / 60
        weeklyAveragePushUps = totalSess > 0 ? Double(totalPU) / Double(totalSess) : 0
    }

    // MARK: - Private: Monthly Stats

    private func rebuildMonthlyStats() {
        let calendar = Calendar.current
        let year  = calendar.component(.year,  from: displayedMonth)
        let month = calendar.component(.month, from: displayedMonth)

        guard let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range    = calendar.range(of: .day, in: .month, for: firstDay) else {
            monthlyWeeks = []; monthlyTotalPushUps = 0; monthlyTotalSessions = 0; monthlyEarnedMinutes = 0
            return
        }

        let sessionsByDay = groupSessionsByDayKey(allSessions)
        var weekMap: [Int: (pushUps: Int, sessions: Int, earned: Int)] = [:]
        var totalPU = 0, totalSess = 0, totalEarned = 0

        for day in range {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
            let weekOfMonth = calendar.component(.weekOfMonth, from: date)
            let key = Self.isoDateFormatter.string(from: date)
            let daySessions = sessionsByDay[key] ?? []
            let pu = daySessions.reduce(0) { $0 + Int($1.pushUpCount) }
            let earned = daySessions.reduce(0) { $0 + Int($1.earnedTimeCreditSeconds) }
            totalPU += pu; totalSess += daySessions.count; totalEarned += earned
            var w = weekMap[weekOfMonth] ?? (0, 0, 0)
            w.pushUps += pu; w.sessions += daySessions.count; w.earned += earned
            weekMap[weekOfMonth] = w
        }

        monthlyWeeks = weekMap.sorted { $0.key < $1.key }.map { weekNum, data in
            let weekStart = calendar.date(from: DateComponents(year: year, month: month, day: (weekNum - 1) * 7 + 1)) ?? firstDay
            return MonthlyWeekData(
                id: weekNum, label: "W\(weekNum)", weekStart: weekStart,
                totalPushUps: data.pushUps, totalSessions: data.sessions,
                totalEarnedMinutes: data.earned / 60
            )
        }

        monthlyTotalPushUps  = totalPU
        monthlyTotalSessions = totalSess
        monthlyEarnedMinutes = totalEarned / 60

        // Month comparison
        let prevMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
        let prevYear  = calendar.component(.year,  from: prevMonth)
        let prevMo    = calendar.component(.month, from: prevMonth)
        let prevPU = allSessions.filter { session in
            let d = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
            return calendar.component(.year, from: d) == prevYear && calendar.component(.month, from: d) == prevMo
        }.reduce(0) { $0 + Int($1.pushUpCount) }

        monthComparison = MonthComparison(currentMonthPushUps: totalPU, previousMonthPushUps: prevPU)
    }

    // MARK: - Private: Total Stats

    private func rebuildTotalStats() {
        guard !allSessions.isEmpty else { totalStats = nil; return }

        let totalPU   = allSessions.reduce(0) { $0 + Int($1.pushUpCount) }
        let totalSess = allSessions.count
        let totalEarned = allSessions.reduce(0) { $0 + Int($1.earnedTimeCreditSeconds) }
        let bestSession = allSessions.map { Int($0.pushUpCount) }.max() ?? 0
        let avgQuality  = allSessions.reduce(0.0) { $0 + Double($1.quality) } / Double(totalSess)
        let avgPU       = Double(totalPU) / Double(totalSess)

        let calendar = Calendar.current
        let sessionsByDay = groupSessionsByDayKey(allSessions)

        let activeDays = sessionsByDay.count
        let bestDay = sessionsByDay.values.map { sessions in
            sessions.reduce(0) { $0 + Int($1.pushUpCount) }
        }.max() ?? 0

        // Streak calculation
        let sortedDayKeys = sessionsByDay.keys.sorted()
        let today = Self.isoDateFormatter.string(from: Date())
        let yesterday = Self.isoDateFormatter.string(from: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date())

        var currentStreak = 0
        var longestStreak = 0
        var runLength = 1

        if !sortedDayKeys.isEmpty {
            for i in 1..<sortedDayKeys.count {
                if let prev = Self.isoDateFormatter.date(from: sortedDayKeys[i-1]),
                   let curr = Self.isoDateFormatter.date(from: sortedDayKeys[i]),
                   let expected = calendar.date(byAdding: .day, value: 1, to: prev),
                   calendar.isDate(curr, inSameDayAs: expected) {
                    runLength += 1
                    longestStreak = max(longestStreak, runLength)
                } else {
                    runLength = 1
                }
            }
            longestStreak = max(longestStreak, runLength)

            let lastKey = sortedDayKeys.last!
            if lastKey == today || lastKey == yesterday {
                currentStreak = 1
                for i in stride(from: sortedDayKeys.count - 1, through: 1, by: -1) {
                    if let curr = Self.isoDateFormatter.date(from: sortedDayKeys[i]),
                       let prev = Self.isoDateFormatter.date(from: sortedDayKeys[i-1]),
                       let expected = calendar.date(byAdding: .day, value: -1, to: curr),
                       calendar.isDate(prev, inSameDayAs: expected) {
                        currentStreak += 1
                    } else {
                        break
                    }
                }
            }
        }

        let totalDuration = allSessions.reduce(0) { total, session in
            guard let endedAt = session.endedAt else { return total }
            return total + Int(endedAt.epochSeconds - session.startedAt.epochSeconds)
        }
        let avgDuration = totalSess > 0 ? totalDuration / totalSess : 0

        totalStats = TotalStatsData(
            totalPushUps: totalPU,
            totalSessions: totalSess,
            totalEarnedMinutes: totalEarned / 60,
            longestStreakDays: longestStreak,
            currentStreakDays: currentStreak,
            averagePushUpsPerSession: avgPU,
            averageSessionDurationSeconds: avgDuration,
            bestSingleSession: bestSession,
            bestDay: bestDay,
            bestWeek: 0,
            activeDays: activeDays,
            averageQuality: avgQuality
        )
    }

    // MARK: - Private: Helpers

    private func groupSessionsByDayKey(_ sessions: [Shared.WorkoutSession]) -> [String: [Shared.WorkoutSession]] {
        Dictionary(grouping: sessions) { session in
            let d = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
            return Self.isoDateFormatter.string(from: d)
        }
    }

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
        guard let monday = calendar.date(byAdding: .day, value: -todayIndex, to: calendar.startOfDay(for: today)) else { return [] }

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
