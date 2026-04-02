import Foundation
import Shared

// MARK: - StatsTab

enum StatsTab: Int, CaseIterable, Identifiable {
    case daily      = 0
    case weekly     = 1
    case monthly    = 2
    case total      = 3
    case screenTime = 4
    case history    = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .daily:      return "Daily"
        case .weekly:     return "Weekly"
        case .monthly:    return "Monthly"
        case .total:      return "Total"
        case .screenTime: return "Screen"
        case .history:    return "History"
        }
    }
}

// MARK: - DayWorkoutData

struct DayWorkoutData: Identifiable {
    let id: String          // "yyyy-MM-dd"
    let date: Date
    let activityPoints: Int
    let sessions: Int
    let earnedMinutes: Int
    let averageQuality: Double

    var hasWorkout: Bool { activityPoints > 0 }
}

// MARK: - WeeklyBarData

struct WeeklyBarData: Identifiable {
    let id: Int
    let label: String
    let date: Date
    let activityPoints: Int
    let sessions: Int
    let earnedMinutes: Int
    let isToday: Bool
}

// MARK: - MonthlyWeekData

struct MonthlyWeekData: Identifiable {
    let id: Int
    let label: String
    let weekStart: Date
    let totalActivityPoints: Int
    let totalSessions: Int
    let totalEarnedMinutes: Int
}

// MARK: - TotalStatsData

struct TotalStatsData {
    let totalActivityPoints: Int
    let totalSessions: Int
    let totalEarnedMinutes: Int
    let longestStreakDays: Int
    let currentStreakDays: Int
    let averageActivityPointsPerSession: Double
    let averageSessionDurationSeconds: Int
    let bestSingleSessionActivityPoints: Int
    let bestDayActivityPoints: Int
    let bestWeekActivityPoints: Int
    let activeDays: Int
    let averageQuality: Double
}

// MARK: - MonthComparison

struct MonthComparison {
    let currentMonthActivityPoints: Int
    let previousMonthActivityPoints: Int

    var changePercent: Int {
        guard previousMonthActivityPoints > 0 else { return 0 }
        let delta = Double(currentMonthActivityPoints - previousMonthActivityPoints)
        return Int((delta / Double(previousMonthActivityPoints)) * 100)
    }

    var isImprovement: Bool { currentMonthActivityPoints >= previousMonthActivityPoints }
}

// MARK: - StatsViewModel

/// Manages all data and state for the Stats screen.
///
/// Observes the local SQLite database via `DataBridge.observeSessions` and
/// `DataBridge.observeJoggingSessions`. All stats are computed in-memory from
/// the combined activity list, so no per-day API calls are needed.
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
    @Published private(set) var weeklyTotalActivityPoints: Int = 0
    @Published private(set) var weeklyAverageActivityPoints: Double = 0
    @Published private(set) var weeklyTotalSessions: Int = 0
    @Published private(set) var weeklyEarnedMinutes: Int = 0

    // Monthly
    @Published private(set) var monthlyWeeks: [MonthlyWeekData] = []
    @Published private(set) var monthComparison: MonthComparison? = nil
    @Published private(set) var monthlyTotalActivityPoints: Int = 0
    @Published private(set) var monthlyTotalSessions: Int = 0
    @Published private(set) var monthlyEarnedMinutes: Int = 0

    // Total
    @Published private(set) var totalStats: TotalStatsData? = nil

    // Loading / Error
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isRefreshing: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Private

    private var workoutSessions: [Shared.WorkoutSession] = []
    private var joggingSessions: [Shared.JoggingSession] = []
    private var observationJob: Kotlinx_coroutines_coreJob?
    private var joggingObservationJob: Kotlinx_coroutines_coreJob?

    // MARK: - Init / Deinit

    init() {}

    deinit {
        observationJob?.cancel(cause: nil)
        joggingObservationJob?.cancel(cause: nil)
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
            self.workoutSessions = sessions.filter { $0.endedAt != nil }
            self.rebuildAllStats()
            self.isLoading = false
            self.isRefreshing = false
        }

        joggingObservationJob = DataBridge.shared.observeJoggingSessions(userId: user.id) { [weak self] sessions in
            guard let self else { return }
            self.joggingSessions = sessions.filter { $0.endedAt != nil }
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

        let sessionsByDay = groupActivityByDayKey(allActivities)

        calendarDays = range.compactMap { day -> DayWorkoutData? in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            let key = Self.isoDateFormatter.string(from: date)
            let daySessions = sessionsByDay[key] ?? []
            let activityPoints = daySessions.reduce(0) { $0 + $1.activityPoints }
            let earned  = daySessions.reduce(0) { $0 + $1.earnedSeconds }
            let quality = daySessions.isEmpty ? 0.0
                : daySessions.reduce(0.0) { $0 + ($1.quality ?? 0.0) } / Double(daySessions.count)
            return DayWorkoutData(
                id: key, date: date, activityPoints: activityPoints,
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

        let sessionsByDay = groupActivityByDayKey(allActivities)
        var totalPoints = 0, totalSess = 0, totalEarned = 0

        weeklyBars = WeekdayHelper.dayLabels.enumerated().map { idx, label in
            let dayDate = calendar.date(byAdding: .day, value: idx, to: monday) ?? monday
            let key = Self.isoDateFormatter.string(from: dayDate)
            let daySessions = sessionsByDay[key] ?? []
            let points = daySessions.reduce(0) { $0 + $1.activityPoints }
            let earned = daySessions.reduce(0) { $0 + $1.earnedSeconds }
            totalPoints += points
            totalSess += daySessions.count
            totalEarned += earned
            return WeeklyBarData(
                id: idx, label: label, date: dayDate,
                activityPoints: points, sessions: daySessions.count,
                earnedMinutes: earned / 60, isToday: idx == todayIndex
            )
        }

        weeklyTotalActivityPoints   = totalPoints
        weeklyTotalSessions  = totalSess
        weeklyEarnedMinutes  = totalEarned / 60
        weeklyAverageActivityPoints = totalSess > 0 ? Double(totalPoints) / Double(totalSess) : 0
    }

    // MARK: - Private: Monthly Stats

    private func rebuildMonthlyStats() {
        let calendar = Calendar.current
        let year  = calendar.component(.year,  from: displayedMonth)
        let month = calendar.component(.month, from: displayedMonth)

        guard let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range    = calendar.range(of: .day, in: .month, for: firstDay) else {
            monthlyWeeks = []; monthlyTotalActivityPoints = 0; monthlyTotalSessions = 0; monthlyEarnedMinutes = 0
            return
        }

        let sessionsByDay = groupActivityByDayKey(allActivities)
        var weekMap: [Int: (activityPoints: Int, sessions: Int, earned: Int)] = [:]
        var totalPoints = 0, totalSess = 0, totalEarned = 0

        for day in range {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
            let weekOfMonth = calendar.component(.weekOfMonth, from: date)
            let key = Self.isoDateFormatter.string(from: date)
            let daySessions = sessionsByDay[key] ?? []
            let points = daySessions.reduce(0) { $0 + $1.activityPoints }
            let earned = daySessions.reduce(0) { $0 + $1.earnedSeconds }
            totalPoints += points; totalSess += daySessions.count; totalEarned += earned
            var w = weekMap[weekOfMonth] ?? (0, 0, 0)
            w.activityPoints += points; w.sessions += daySessions.count; w.earned += earned
            weekMap[weekOfMonth] = w
        }

        monthlyWeeks = weekMap.sorted { $0.key < $1.key }.map { weekNum, data in
            let weekStart = calendar.date(from: DateComponents(year: year, month: month, day: (weekNum - 1) * 7 + 1)) ?? firstDay
            return MonthlyWeekData(
                id: weekNum, label: "W\(weekNum)", weekStart: weekStart,
                totalActivityPoints: data.activityPoints, totalSessions: data.sessions,
                totalEarnedMinutes: data.earned / 60
            )
        }

        monthlyTotalActivityPoints  = totalPoints
        monthlyTotalSessions = totalSess
        monthlyEarnedMinutes = totalEarned / 60

        // Month comparison
        let prevMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
        let prevYear  = calendar.component(.year,  from: prevMonth)
        let prevMo    = calendar.component(.month, from: prevMonth)
        let prevPoints = allActivities.filter { session in
            let d = session.date
            return calendar.component(.year, from: d) == prevYear && calendar.component(.month, from: d) == prevMo
        }.reduce(0) { $0 + $1.activityPoints }

        monthComparison = MonthComparison(currentMonthActivityPoints: totalPoints, previousMonthActivityPoints: prevPoints)
    }

    // MARK: - Private: Total Stats

    private func rebuildTotalStats() {
        guard !allActivities.isEmpty else { totalStats = nil; return }

        let totalPoints   = allActivities.reduce(0) { $0 + $1.activityPoints }
        let totalSess = allActivities.count
        let totalEarned = allActivities.reduce(0) { $0 + $1.earnedSeconds }
        let bestSession = allActivities.map { $0.activityPoints }.max() ?? 0
        let qualityValues = allActivities.compactMap(\.quality)
        let avgQuality  = qualityValues.isEmpty ? 0.0 : qualityValues.reduce(0.0, +) / Double(qualityValues.count)
        let avgPoints       = Double(totalPoints) / Double(totalSess)

        let calendar = Calendar.current
        let sessionsByDay = groupActivityByDayKey(allActivities)

        let activeDays = sessionsByDay.count
        let bestDay = sessionsByDay.values.map { sessions in
            sessions.reduce(0) { $0 + $1.activityPoints }
        }.max() ?? 0
        let groupedWeeks = Dictionary(grouping: allActivities) { activity in
            calendar.dateInterval(of: .weekOfYear, for: activity.date)?.start ?? calendar.startOfDay(for: activity.date)
        }
        let bestWeek = groupedWeeks.values.map { sessions in
            sessions.reduce(0) { $0 + $1.activityPoints }
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

        let totalDuration = allActivities.reduce(0) { total, session in
            total + session.durationSeconds
        }
        let avgDuration = totalSess > 0 ? totalDuration / totalSess : 0

        totalStats = TotalStatsData(
            totalActivityPoints: totalPoints,
            totalSessions: totalSess,
            totalEarnedMinutes: totalEarned / 60,
            longestStreakDays: longestStreak,
            currentStreakDays: currentStreak,
            averageActivityPointsPerSession: avgPoints,
            averageSessionDurationSeconds: avgDuration,
            bestSingleSessionActivityPoints: bestSession,
            bestDayActivityPoints: bestDay,
            bestWeekActivityPoints: bestWeek,
            activeDays: activeDays,
            averageQuality: avgQuality
        )
    }

    // MARK: - Private: Helpers

    private func groupActivityByDayKey(_ sessions: [ActivityEntry]) -> [String: [ActivityEntry]] {
        Dictionary(grouping: sessions) { session in
            Self.isoDateFormatter.string(from: session.date)
        }
    }

    private func applyEmptyState() {
        calendarDays         = []
        weeklyBars           = Self.makeEmptyWeeklyBars()
        weeklyTotalActivityPoints   = 0
        weeklyAverageActivityPoints = 0
        weeklyTotalSessions  = 0
        weeklyEarnedMinutes  = 0
        monthlyWeeks         = []
        monthlyTotalActivityPoints  = 0
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
            return WeeklyBarData(id: idx, label: label, date: date, activityPoints: 0, sessions: 0, earnedMinutes: 0, isToday: idx == todayIndex)
        }
    }

    private var allActivities: [ActivityEntry] {
        let workouts = workoutSessions.compactMap { session -> ActivityEntry? in
            guard let endedAt = session.endedAt else { return nil }
            let startedAt = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
            let duration = Int(endedAt.epochSeconds - session.startedAt.epochSeconds)
            return ActivityEntry(
                date: startedAt,
                activityPoints: workoutXp(pushUpCount: Int(session.pushUpCount), quality: Double(session.quality)),
                earnedSeconds: Int(session.earnedTimeCreditSeconds),
                quality: Double(session.quality),
                durationSeconds: max(0, duration)
            )
        }
        let joggings = joggingSessions.compactMap { session -> ActivityEntry? in
            guard let endedAt = session.endedAt else { return nil }
            let startedAt = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
            let duration = Int(endedAt.epochSeconds - session.startedAt.epochSeconds)
            let distanceUnits = Int(session.distanceMeters / 100.0)
            return ActivityEntry(
                date: startedAt,
                activityPoints: distanceUnits * 10,
                earnedSeconds: Int(session.earnedTimeCreditSeconds),
                quality: nil,
                durationSeconds: max(0, duration)
            )
        }
        return (workouts + joggings).sorted { $0.date < $1.date }
    }

    private func workoutXp(pushUpCount: Int, quality: Double) -> Int {
        let multiplier: Double
        switch quality {
        case let q where q > 0.8: multiplier = 1.5
        case 0.5...: multiplier = 1.0
        default: multiplier = 0.7
        }
        return Int(Double(pushUpCount * 10) * multiplier)
    }

    private struct ActivityEntry {
        let date: Date
        let activityPoints: Int
        let earnedSeconds: Int
        let quality: Double?
        let durationSeconds: Int
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
