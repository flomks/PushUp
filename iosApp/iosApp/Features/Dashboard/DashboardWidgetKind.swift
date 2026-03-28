import Foundation

// MARK: - DashboardWidgetKind

/// Identifies a dashboard block the user can show, hide, and reorder.
enum DashboardWidgetKind: String, CaseIterable, Hashable {
    case timeCredit
    case screenTime
    case dailyStats
    case weeklyChart
    case activitySummary
    case workoutQuickAction

    /// Default layout matches the original dashboard order.
    static let defaultOrder: [DashboardWidgetKind] = allCases

    var title: String {
        switch self {
        case .timeCredit: return "Time Credit"
        case .screenTime: return "Screen Time"
        case .dailyStats: return "Daily Stats"
        case .weeklyChart: return "Weekly Chart"
        case .activitySummary: return "Last Activity"
        case .workoutQuickAction: return "Choose Workout"
        }
    }

    var systemImage: String {
        switch self {
        case .timeCredit: return "clock.arrow.circlepath"
        case .screenTime: return "hourglass"
        case .dailyStats: return "chart.bar.fill"
        case .weeklyChart: return "chart.bar.xaxis"
        case .activitySummary: return "clock.arrow.circlepath"
        case .workoutQuickAction: return "figure.strengthtraining.traditional"
        }
    }
}
