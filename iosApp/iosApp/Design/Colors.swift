import SwiftUI

// MARK: - AppColors

/// Centralised color palette for the PushUp app.
///
/// All colors support Light and Dark appearance automatically. Colors are
/// defined in code using adaptive `UIColor` initialisers so the design system
/// is self-contained -- no Asset Catalog dependency required.
///
/// Usage:
/// ```swift
/// Text("Hello")
///     .foregroundStyle(AppColors.textPrimary)
///     .background(AppColors.backgroundPrimary)
/// ```
enum AppColors {

    // MARK: - Primary

    /// Main brand color -- vibrant blue for primary actions and accents.
    /// Light: #007AFF  Dark: #0A84FF
    static let primary = Color(light: "#007AFF", dark: "#0A84FF")

    /// Muted variant for pressed / secondary interactive states.
    /// Light: #5AC8FA  Dark: #64D2FF
    static let primaryVariant = Color(light: "#5AC8FA", dark: "#64D2FF")

    // MARK: - Secondary

    /// Accent color for highlights, badges, and secondary CTAs.
    /// Light: #FF6B35  Dark: #FF9F0A
    static let secondary = Color(light: "#FF6B35", dark: "#FF9F0A")

    /// Muted secondary for less prominent elements.
    /// Light: #FFD60A  Dark: #FFD60A
    static let secondaryVariant = Color(light: "#FFD60A", dark: "#FFD60A")

    // MARK: - Background

    /// Primary screen background.
    /// Light: #F2F2F7  Dark: #000000
    static let backgroundPrimary = Color(light: "#F2F2F7", dark: "#000000")

    /// Secondary background for cards, sheets, grouped rows.
    /// Light: #FFFFFF  Dark: #1C1C1E
    static let backgroundSecondary = Color(light: "#FFFFFF", dark: "#1C1C1E")

    /// Tertiary background for nested containers and input fields.
    /// Light: #E5E5EA  Dark: #2C2C2E
    static let backgroundTertiary = Color(light: "#E5E5EA", dark: "#2C2C2E")

    // MARK: - Text

    /// Primary text -- highest contrast for headings and body copy.
    /// Light: #000000  Dark: #FFFFFF
    static let textPrimary = Color(light: "#000000", dark: "#FFFFFF")

    /// Secondary text -- subtitles, labels, supporting copy.
    /// Light: #3C3C43 @ 60%  Dark: #EBEBF5 @ 60%
    static let textSecondary = Color(
        uiColor: UIColor(
            light: UIColor(red: 0.235, green: 0.235, blue: 0.263, alpha: 0.6),
            dark:  UIColor(red: 0.922, green: 0.922, blue: 0.961, alpha: 0.6)
        )
    )

    /// Tertiary text -- placeholders and disabled states.
    /// Light: #3C3C43 @ 30%  Dark: #EBEBF5 @ 30%
    static let textTertiary = Color(
        uiColor: UIColor(
            light: UIColor(red: 0.235, green: 0.235, blue: 0.263, alpha: 0.3),
            dark:  UIColor(red: 0.922, green: 0.922, blue: 0.961, alpha: 0.3)
        )
    )

    /// Text on primary-colored backgrounds (e.g. button labels).
    static let textOnPrimary = Color.white

    // MARK: - Semantic / Status

    /// Success -- positive feedback, completed reps, good form.
    /// Light: #34C759  Dark: #30D158
    static let success = Color(light: "#34C759", dark: "#30D158")

    /// Warning -- moderate form issues, low credit warnings.
    /// Light: #FF9500  Dark: #FF9F0A
    static let warning = Color(light: "#FF9500", dark: "#FF9F0A")

    /// Error / destructive -- poor form, empty credit, errors.
    /// Light: #FF3B30  Dark: #FF453A
    static let error = Color(light: "#FF3B30", dark: "#FF453A")

    /// Informational -- tips and neutral status indicators.
    /// Light: #5AC8FA  Dark: #64D2FF
    static let info = Color(light: "#5AC8FA", dark: "#64D2FF")

    // MARK: - Surface / Overlay

    /// Separator lines and dividers.
    /// Light: #C6C6C8  Dark: #38383A
    static let separator = Color(light: "#C6C6C8", dark: "#38383A")

    /// Subtle fill for interactive elements in resting state.
    /// Light: #F2F2F7  Dark: #2C2C2E
    static let fill = Color(light: "#F2F2F7", dark: "#2C2C2E")

    // MARK: - Workout-specific

    /// "DOWN" phase indicator during a push-up.
    static let phaseDown: Color = error

    /// "UP / cooldown" phase indicator during a push-up.
    static let phaseUp: Color = success

    /// Idle / ready phase indicator.
    static let phaseIdle: Color = textSecondary

    // MARK: - Form Score

    /// Returns an adaptive color for a form score in [0, 1].
    ///
    /// - 0.75 ... 1.0 -> success (green)
    /// - 0.50 ... 0.74 -> warning (orange)
    /// - 0.00 ... 0.49 -> error (red)
    static func formScoreColor(_ score: Double) -> Color {
        switch score {
        case 0.75...: return success
        case 0.50...: return warning
        default:      return error
        }
    }
}

// MARK: - Adaptive Color Helpers

extension Color {

    /// Creates an adaptive color from explicit light and dark hex strings.
    init(light: String, dark: String) {
        self.init(uiColor: UIColor(light: UIColor(hex: light), dark: UIColor(hex: dark)))
    }
}

extension UIColor {

    /// Initialises a `UIColor` from a CSS-style hex string.
    /// Supports `#RRGGBB` and `#RRGGBBAA` formats.
    convenience init(hex: String) {
        let sanitised = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: sanitised).scanHexInt64(&rgb)

        let r, g, b, a: CGFloat

        switch sanitised.count {
        case 6:
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255
            g = CGFloat((rgb & 0x00FF00) >> 8)  / 255
            b = CGFloat(rgb & 0x0000FF)          / 255
            a = 1.0
        case 8:
            r = CGFloat((rgb & 0xFF00_0000) >> 24) / 255
            g = CGFloat((rgb & 0x00FF_0000) >> 16) / 255
            b = CGFloat((rgb & 0x0000_FF00) >> 8)  / 255
            a = CGFloat(rgb & 0x0000_00FF)          / 255
        default:
            assertionFailure("Invalid hex color string: \(hex)")
            r = 0; g = 0; b = 0; a = 1
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }

    /// Creates an adaptive `UIColor` that resolves per-appearance.
    convenience init(light: UIColor, dark: UIColor) {
        self.init { $0.userInterfaceStyle == .dark ? dark : light }
    }
}
