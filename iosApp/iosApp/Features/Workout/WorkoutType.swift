import SwiftUI

// MARK: - WorkoutType

/// Represents the available exercise types in the app.
///
/// Each case carries all display metadata (icon, name, description, color,
/// earned-time formula hint) so the workout selection grid can be built
/// entirely from this enum without scattering strings across multiple files.
///
/// **Available exercises**
/// - `pushUps`: Camera-tracked push-ups (fully implemented).
/// - `plank`: Timed plank hold (timer-based).
/// - `jumpingJacks`: Counted jumping jacks (timer-based).
/// - `squats`: Counted squats (timer-based).
/// - `crunches`: Counted crunches (timer-based).
/// - `jogging`: GPS-tracked jogging (coming soon, requires full tracking).
enum WorkoutType: String, CaseIterable, Identifiable, Hashable {
    case pushUps
    case plank
    case jumpingJacks
    case squats
    case crunches
    case jogging

    // MARK: Identifiable

    var id: String { rawValue }

    // MARK: - Display Metadata

    /// The user-facing name of the exercise.
    var displayName: String {
        switch self {
        case .pushUps:      return "Push-Ups"
        case .plank:        return "Plank"
        case .jumpingJacks: return "Jumping Jacks"
        case .squats:       return "Squats"
        case .crunches:     return "Crunches"
        case .jogging:      return "Jogging"
        }
    }

    /// A short description of the exercise shown below the name.
    var subtitle: String {
        switch self {
        case .pushUps:      return "Camera-tracked reps"
        case .plank:        return "Timed hold"
        case .jumpingJacks: return "Count your reps"
        case .squats:       return "Count your reps"
        case .crunches:     return "Count your reps"
        case .jogging:      return "Coming soon"
        }
    }

    /// A brief motivational hint about how screen time is earned.
    var earnHint: String {
        switch self {
        case .pushUps:      return "1 min per 10 reps"
        case .plank:        return "1 min per 30s held"
        case .jumpingJacks: return "1 min per 20 reps"
        case .squats:       return "1 min per 15 reps"
        case .crunches:     return "1 min per 15 reps"
        case .jogging:      return "Track with GPS"
        }
    }

    /// The SF Symbol icon for this exercise.
    var icon: AppIcon {
        switch self {
        case .pushUps:      return .figureStrengthTraining
        case .plank:        return .figurePilates
        case .jumpingJacks: return .figureJumpRope
        case .squats:       return .figureCrossTraining
        case .crunches:     return .figureCoreTraining
        case .jogging:      return .figureRun
        }
    }

    /// The accent color used for this exercise's card and UI elements.
    var accentColor: Color {
        switch self {
        case .pushUps:      return AppColors.primary
        case .plank:        return AppColors.secondary
        case .jumpingJacks: return AppColors.success
        case .squats:       return Color(light: "#8B5CF6", dark: "#A78BFA")
        case .crunches:     return AppColors.warning
        case .jogging:      return AppColors.info
        }
    }

    /// The gradient colors used for the exercise card background.
    var gradientColors: [Color] {
        switch self {
        case .pushUps:      return [AppColors.primary, AppColors.primary.opacity(0.7)]
        case .plank:        return [AppColors.secondary, AppColors.secondary.opacity(0.7)]
        case .jumpingJacks: return [AppColors.success, AppColors.success.opacity(0.7)]
        case .squats:       return [Color(light: "#8B5CF6", dark: "#A78BFA"), Color(light: "#8B5CF6", dark: "#A78BFA").opacity(0.7)]
        case .crunches:     return [AppColors.warning, AppColors.warning.opacity(0.7)]
        case .jogging:      return [AppColors.info, AppColors.info.opacity(0.7)]
        }
    }

    /// Whether this exercise is fully implemented and available to use.
    var isAvailable: Bool {
        switch self {
        case .pushUps, .plank, .jumpingJacks, .squats, .crunches:
            return true
        case .jogging:
            return false
        }
    }

    /// Whether this exercise uses camera-based tracking.
    var usesCameraTracking: Bool {
        switch self {
        case .pushUps:
            return true
        default:
            return false
        }
    }

    /// The difficulty level displayed as a visual indicator.
    var difficulty: Difficulty {
        switch self {
        case .pushUps:      return .medium
        case .plank:        return .hard
        case .jumpingJacks: return .easy
        case .squats:       return .medium
        case .crunches:     return .medium
        case .jogging:      return .easy
        }
    }

    // MARK: - Difficulty

    enum Difficulty: String {
        case easy
        case medium
        case hard

        var displayName: String {
            switch self {
            case .easy:   return "Easy"
            case .medium: return "Medium"
            case .hard:   return "Hard"
            }
        }

        var color: Color {
            switch self {
            case .easy:   return AppColors.success
            case .medium: return AppColors.warning
            case .hard:   return AppColors.error
            }
        }

        var dotCount: Int {
            switch self {
            case .easy:   return 1
            case .medium: return 2
            case .hard:   return 3
            }
        }
    }
}
