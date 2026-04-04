import Foundation

// MARK: - DashboardWidgetKind

/// Identifies a dashboard block the user can show, hide, and reorder.
/// Raw values are persisted as JSON — do not rename existing cases.
enum DashboardWidgetKind: String, CaseIterable, Hashable {

    // MARK: Core (original defaults)

    case timeCredit
    case screenTime
    case dailyStats
    case weeklyChart
    case activitySummary
    case workoutQuickAction

    // MARK: Push-ups & strength

    case pushUpsThisWeek
    case pushUpsThisMonth
    case pushUpsAllTime
    case pushUpSessionsWeek
    case bestPushUpSession
    case averageFormWeek
    case streakCurrent
    case streakBest

    // MARK: Running / jogging

    case runDistanceToday
    case runDistanceWeek
    case runDistanceMonth
    case runDistanceAllTime
    case runSessionsWeek

    // MARK: Time credit (compact)

    case creditEarnedToday
    case creditSpentToday
    case creditTotalEarned
    case creditLifetimeSpent

    // MARK: Combined activity

    case activeMinutesWeek
    case allSessionsWeek

    // MARK: Shortcuts

    case shortcutStats
    case shortcutProfile
    case shortcutFriends
    case shortcutSettings

    /// First-time and reset layout: only the original widgets. New types are opt-in via “Add widget”.
    static let defaultOrder: [DashboardWidgetKind] = [
        .timeCredit,
        .screenTime,
        .dailyStats,
        .weeklyChart,
        .activitySummary,
        .workoutQuickAction,
    ]

    var title: String {
        switch self {
        case .timeCredit: return "Time Credit"
        case .screenTime: return "Screen Time"
        case .dailyStats: return "Today’s Stats"
        case .weeklyChart: return "Weekly Chart"
        case .activitySummary: return "Last Activity"
        case .workoutQuickAction: return "Choose Workout"

        case .pushUpsThisWeek: return "Push-ups (this week)"
        case .pushUpsThisMonth: return "Push-ups (this month)"
        case .pushUpsAllTime: return "Push-ups (all time)"
        case .pushUpSessionsWeek: return "Strength sessions (week)"
        case .bestPushUpSession: return "Best session (reps)"
        case .averageFormWeek: return "Avg form (week)"
        case .streakCurrent: return "Current streak"
        case .streakBest: return "Best streak"

        case .runDistanceToday: return "Run distance (today)"
        case .runDistanceWeek: return "Run distance (week)"
        case .runDistanceMonth: return "Run distance (month)"
        case .runDistanceAllTime: return "Run distance (all time)"
        case .runSessionsWeek: return "Run sessions (week)"

        case .creditEarnedToday: return "Credit earned (today)"
        case .creditSpentToday: return "Screen time used (today)"
        case .creditTotalEarned: return "Total credit earned"
        case .creditLifetimeSpent: return "Total screen time spent"

        case .activeMinutesWeek: return "Active minutes (week)"
        case .allSessionsWeek: return "All sessions (week)"

        case .shortcutStats: return "Open Stats"
        case .shortcutProfile: return "Open Profile"
        case .shortcutFriends: return "Open Friends"
        case .shortcutSettings: return "Open Settings"
        }
    }

    /// Whether this widget can be placed inside a dashboard grid cell.
    /// Only compact / stat widgets qualify — content-heavy widgets need full width.
    var isGridEligible: Bool {
        switch self {
        case .timeCredit, .screenTime, .dailyStats, .weeklyChart,
             .activitySummary, .workoutQuickAction:
            return false
        default:
            return true
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

        case .pushUpsThisWeek, .pushUpsThisMonth, .pushUpsAllTime, .bestPushUpSession:
            return "figure.strengthtraining.traditional"
        case .pushUpSessionsWeek: return "repeat.circle.fill"
        case .averageFormWeek: return "waveform.path.ecg"
        case .streakCurrent: return "flame.fill"
        case .streakBest: return "trophy.fill"

        case .runDistanceToday, .runDistanceWeek, .runDistanceMonth, .runDistanceAllTime:
            return "figure.run"
        case .runSessionsWeek: return "shoeprints.fill"

        case .creditEarnedToday: return "plus.circle.fill"
        case .creditSpentToday: return "minus.circle.fill"
        case .creditTotalEarned: return "banknote.fill"
        case .creditLifetimeSpent: return "hourglass.bottomhalf.filled"

        case .activeMinutesWeek: return "timer"
        case .allSessionsWeek: return "square.stack.fill"

        case .shortcutStats: return "chart.bar.fill"
        case .shortcutProfile: return "person.fill"
        case .shortcutFriends: return "person.2.fill"
        case .shortcutSettings: return "gearshape.fill"
        }
    }
}
