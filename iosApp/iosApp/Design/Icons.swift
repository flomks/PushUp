import SwiftUI

// MARK: - AppIcon

/// Type-safe SF Symbol references used throughout the app.
///
/// Using this enum instead of raw strings prevents silent failures from
/// typos -- a misspelled case name is a compile error, while a misspelled
/// string produces an invisible empty image at runtime.
///
/// Usage:
/// ```swift
/// Image(systemName: AppIcon.figureRun.rawValue)
///
/// Label("Workout", systemImage: AppIcon.figureRun.rawValue)
///
/// IconButton(.arrowCounterclockwise, label: "Reset") { ... }
/// ```
enum AppIcon: String {

    // MARK: - Navigation / Tabs

    case house              = "house"
    case houseFill          = "house.fill"
    case figureRun          = "figure.run"
    case chartBar           = "chart.bar"
    case chartBarFill       = "chart.bar.fill"
    case person             = "person"
    case personFill         = "person.fill"
    case gearshape          = "gearshape"
    case gearshapeFill      = "gearshape.fill"

    // MARK: - Workout

    case figureStrengthTraining = "figure.strengthtraining.traditional"
    case figureArmsOpen     = "figure.arms.open"
    case figureStand        = "figure.stand"
    case timer              = "timer"
    case clock              = "clock"
    case clockArrowCirclepath = "clock.arrow.circlepath"
    case boltFill           = "bolt.fill"

    // MARK: - Pose / Camera

    case camera             = "camera"
    case cameraViewfinder   = "camera.viewfinder"
    case cameraRotate       = "camera.rotate"
    case eye                = "eye"
    case eyeSlash           = "eye.slash"
    case personSlash        = "person.slash"
    case person2            = "person.2"
    case angle              = "angle"

    // MARK: - Status / Feedback

    case checkmarkCircle    = "checkmark.circle"
    case checkmarkCircleFill = "checkmark.circle.fill"
    case xmarkCircle        = "xmark.circle"
    case exclamationmarkTriangle = "exclamationmark.triangle"
    case infoCircle         = "info.circle"
    case infoCircleFill     = "info.circle.fill"

    // MARK: - Stats / Metrics

    case starFill           = "star.fill"
    case flameFill          = "flame.fill"
    case calendarBadgeCheckmark = "calendar.badge.checkmark"
    case arrowUpRight       = "arrow.up.right"
    case arrowDownRight     = "arrow.down.right"

    // MARK: - Actions

    case arrowRight         = "arrow.right"
    case arrowRightSquare   = "arrow.right.square"
    case arrowCounterclockwise = "arrow.counterclockwise"
    case arrowDownCircleFill = "arrow.down.circle.fill"
    case checkmark          = "checkmark"
    case trash              = "trash"
    case squareAndArrowUp   = "square.and.arrow.up"
    case paperplane         = "paperplane"
    case play               = "play"
    case playFill           = "play.fill"
    case pause              = "pause"
    case pauseFill          = "pause.fill"
    case stop               = "stop"
    case stopFill           = "stop.fill"

    // MARK: - Warnings

    case sunMin             = "sun.min"
    case arrowLeftAndRightSquare = "arrow.left.and.right.square"

    // MARK: - Auth / Onboarding

    case envelope           = "envelope"
    case envelopeFill       = "envelope.fill"
    case lock               = "lock"
    case lockRotation       = "lock.rotation"
    case appleLogo          = "apple.logo"
    case globe              = "globe"
    case personBadgePlus    = "person.badge.plus"
    case clockBadgeCheckmark = "clock.badge.checkmark"
    case exclamationmarkCircleFill = "exclamationmark.circle.fill"

    // MARK: - History / Search

    case clockFill          = "clock.fill"
    case listBullet         = "list.bullet"
    case listBulletClipboard = "list.bullet.clipboard"
    case rectangleStack     = "rectangle.stack"
    case rectangleStackFill = "rectangle.stack.fill"
    case magnifyingglass    = "magnifyingglass"
    case xmarkCircleFill    = "xmark.circle.fill"
    case chevronRight       = "chevron.right"
    case star               = "star"

    // MARK: - Misc

    case minus              = "minus"
}

// MARK: - Convenience

extension Image {
    /// Creates an SF Symbol image from a type-safe `AppIcon`.
    init(icon: AppIcon) {
        self.init(systemName: icon.rawValue)
    }
}

extension Label where Title == Text, Icon == Image {
    /// Creates a label with a type-safe `AppIcon`.
    init(_ title: String, icon: AppIcon) {
        self.init(title, systemImage: icon.rawValue)
    }
}
