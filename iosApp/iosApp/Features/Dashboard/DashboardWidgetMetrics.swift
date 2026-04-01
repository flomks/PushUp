import Foundation

// MARK: - DashboardWidgetMetrics

/// Pre-aggregated numbers for optional dashboard mini-widgets (push-ups, running, streaks, etc.).
/// Updated together with the main dashboard rebuild so widgets stay in sync.
struct DashboardWidgetMetrics: Equatable {
    var pushUpsWeek: Int
    var pushUpsMonth: Int
    var pushUpsAllTime: Int
    var pushUpSessionsWeek: Int
    var bestPushUpSession: Int
    /// Average form score [0, 1] for push-up sessions in the current calendar week.
    var averageFormWeek: Double
    var streakCurrentDays: Int
    var streakLongestDays: Int

    var runDistanceTodayMeters: Int
    var runDistanceWeekMeters: Int
    var runDistanceMonthMeters: Int
    var runDistanceAllTimeMeters: Int
    var runSessionsWeek: Int
    var runSessionsAllTime: Int

    var activeMinutesWeek: Int
    var totalSessionsWeek: Int

    static let empty = DashboardWidgetMetrics(
        pushUpsWeek: 0,
        pushUpsMonth: 0,
        pushUpsAllTime: 0,
        pushUpSessionsWeek: 0,
        bestPushUpSession: 0,
        averageFormWeek: 0,
        streakCurrentDays: 0,
        streakLongestDays: 0,
        runDistanceTodayMeters: 0,
        runDistanceWeekMeters: 0,
        runDistanceMonthMeters: 0,
        runDistanceAllTimeMeters: 0,
        runSessionsWeek: 0,
        runSessionsAllTime: 0,
        activeMinutesWeek: 0,
        totalSessionsWeek: 0
    )
}
