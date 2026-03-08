import SwiftUI

// MARK: - AppColors

/// Centralised color palette for the PushUp app.
///
/// All colors are defined as static properties on `AppColors` and support
/// both Light and Dark appearance automatically via SwiftUI's adaptive color
/// system. Use these constants throughout the app instead of raw `Color`
/// literals to ensure a consistent look and easy theme updates.
///
/// Usage:
/// ```swift
/// Text("Hello")
///     .foregroundStyle(AppColors.textPrimary)
///     .background(AppColors.backgroundPrimary)
/// ```
public enum AppColors {

    // MARK: - Primary

    /// Main brand color -- vibrant blue used for primary actions and accents.
    /// Light: #007AFF (iOS system blue)  Dark: #0A84FF
    public static let primary = Color("AppPrimary", bundle: nil)

    /// Slightly muted variant of the primary color for pressed / secondary
    /// interactive states.
    /// Light: #5AC8FA  Dark: #64D2FF
    public static let primaryVariant = Color("AppPrimaryVariant", bundle: nil)

    // MARK: - Secondary

    /// Accent color used for highlights, badges, and secondary CTAs.
    /// Light: #FF6B35 (energetic orange)  Dark: #FF9F0A
    public static let secondary = Color("AppSecondary", bundle: nil)

    /// Muted secondary for less prominent secondary elements.
    /// Light: #FFD60A  Dark: #FFD60A
    public static let secondaryVariant = Color("AppSecondaryVariant", bundle: nil)

    // MARK: - Background

    /// Primary background of screens and full-bleed containers.
    /// Light: #F2F2F7  Dark: #000000
    public static let backgroundPrimary = Color("AppBackgroundPrimary", bundle: nil)

    /// Secondary background for cards, sheets, and grouped list rows.
    /// Light: #FFFFFF  Dark: #1C1C1E
    public static let backgroundSecondary = Color("AppBackgroundSecondary", bundle: nil)

    /// Tertiary background for nested containers and input fields.
    /// Light: #E5E5EA  Dark: #2C2C2E
    public static let backgroundTertiary = Color("AppBackgroundTertiary", bundle: nil)

    // MARK: - Text

    /// Primary text color -- highest contrast, used for headings and body copy.
    /// Light: #000000  Dark: #FFFFFF
    public static let textPrimary = Color("AppTextPrimary", bundle: nil)

    /// Secondary text color -- used for subtitles, labels, and supporting copy.
    /// Light: #3C3C43 @ 60%  Dark: #EBEBF5 @ 60%
    public static let textSecondary = Color("AppTextSecondary", bundle: nil)

    /// Tertiary text color -- used for placeholders and disabled states.
    /// Light: #3C3C43 @ 30%  Dark: #EBEBF5 @ 30%
    public static let textTertiary = Color("AppTextTertiary", bundle: nil)

    /// Text color used on top of primary-colored backgrounds (e.g. button labels).
    public static let textOnPrimary = Color.white

    // MARK: - Semantic / Status

    /// Success state -- used for positive feedback, completed reps, good form.
    /// Light: #34C759  Dark: #30D158
    public static let success = Color("AppSuccess", bundle: nil)

    /// Warning state -- used for moderate form issues, low credit warnings.
    /// Light: #FF9500  Dark: #FF9F0A
    public static let warning = Color("AppWarning", bundle: nil)

    /// Error / destructive state -- used for poor form, empty credit, errors.
    /// Light: #FF3B30  Dark: #FF453A
    public static let error = Color("AppError", bundle: nil)

    /// Informational state -- used for tips and neutral status indicators.
    /// Light: #5AC8FA  Dark: #64D2FF
    public static let info = Color("AppInfo", bundle: nil)

    // MARK: - Surface / Overlay

    /// Separator lines and dividers.
    /// Light: #C6C6C8  Dark: #38383A
    public static let separator = Color("AppSeparator", bundle: nil)

    /// Subtle fill for interactive elements in their resting state.
    /// Light: #F2F2F7  Dark: #2C2C2E
    public static let fill = Color("AppFill", bundle: nil)

    // MARK: - Workout-specific

    /// Color for the "DOWN" phase indicator during a push-up.
    public static let phaseDown: Color = error

    /// Color for the "UP / cooldown" phase indicator during a push-up.
    public static let phaseUp: Color = success

    /// Color for the idle / ready phase indicator.
    public static let phaseIdle: Color = textSecondary

    // MARK: - Form score gradient

    /// Returns an adaptive color for a form score in [0, 1].
    /// 0.0 – 0.49 -> error (red)
    /// 0.5 – 0.74 -> warning (orange)
    /// 0.75 – 1.0 -> success (green)
    public static func formScoreColor(_ score: Double) -> Color {
        switch score {
        case 0.75...: return success
        case 0.5...:  return warning
        default:      return error
        }
    }
}

// MARK: - Adaptive Color Helpers (SwiftUI)

public extension Color {

    // MARK: Convenience initialisers that mirror AppColors

    /// Creates an adaptive color from explicit light and dark hex strings.
    /// - Parameters:
    ///   - light: Hex string for light appearance (e.g. `"#007AFF"`).
    ///   - dark:  Hex string for dark appearance (e.g. `"#0A84FF"`).
    init(light: String, dark: String) {
        self.init(uiColor: UIColor(light: UIColor(hex: light), dark: UIColor(hex: dark)))
    }
}

// MARK: - UIColor Hex Initialiser

public extension UIColor {

    /// Initialises a `UIColor` from a CSS-style hex string.
    /// Supports `#RGB`, `#RRGGBB`, and `#RRGGBBAA` formats.
    convenience init(hex: String) {
        var hexSanitised = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitised = hexSanitised.hasPrefix("#") ? String(hexSanitised.dropFirst()) : hexSanitised

        var rgb: UInt64 = 0
        Scanner(string: hexSanitised).scanHexInt64(&rgb)

        let length = hexSanitised.count
        let r, g, b, a: CGFloat

        switch length {
        case 6:
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255
            g = CGFloat((rgb & 0x00FF00) >> 8)  / 255
            b = CGFloat(rgb & 0x0000FF)          / 255
            a = 1.0
        case 8:
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255
            b = CGFloat((rgb & 0x0000FF00) >> 8)  / 255
            a = CGFloat(rgb & 0x000000FF)          / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }

    /// Creates an adaptive `UIColor` that switches between light and dark variants.
    convenience init(light: UIColor, dark: UIColor) {
        self.init { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? dark : light
        }
    }
}

// MARK: - Inline Adaptive Colors (no Asset Catalog required)
//
// The `AppColors` enum above references named colors from the Asset Catalog
// (`Color("AppPrimary", bundle: nil)`). If you prefer to keep everything in
// code without an Asset Catalog, replace those references with the inline
// adaptive colors defined below.

public extension AppColors {

    // MARK: Inline definitions (code-only, no Asset Catalog)

    /// Primary brand color -- inline adaptive variant.
    static let primaryInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#007AFF"),
            dark:  UIColor(hex: "#0A84FF")
        )
    )

    static let primaryVariantInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#5AC8FA"),
            dark:  UIColor(hex: "#64D2FF")
        )
    )

    static let secondaryInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#FF6B35"),
            dark:  UIColor(hex: "#FF9F0A")
        )
    )

    static let secondaryVariantInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#FFD60A"),
            dark:  UIColor(hex: "#FFD60A")
        )
    )

    static let backgroundPrimaryInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#F2F2F7"),
            dark:  UIColor(hex: "#000000")
        )
    )

    static let backgroundSecondaryInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#FFFFFF"),
            dark:  UIColor(hex: "#1C1C1E")
        )
    )

    static let backgroundTertiaryInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#E5E5EA"),
            dark:  UIColor(hex: "#2C2C2E")
        )
    )

    static let textPrimaryInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#000000"),
            dark:  UIColor(hex: "#FFFFFF")
        )
    )

    static let textSecondaryInline = Color(
        uiColor: UIColor(
            light: UIColor(red: 0.235, green: 0.235, blue: 0.263, alpha: 0.6),
            dark:  UIColor(red: 0.922, green: 0.922, blue: 0.961, alpha: 0.6)
        )
    )

    static let textTertiaryInline = Color(
        uiColor: UIColor(
            light: UIColor(red: 0.235, green: 0.235, blue: 0.263, alpha: 0.3),
            dark:  UIColor(red: 0.922, green: 0.922, blue: 0.961, alpha: 0.3)
        )
    )

    static let successInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#34C759"),
            dark:  UIColor(hex: "#30D158")
        )
    )

    static let warningInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#FF9500"),
            dark:  UIColor(hex: "#FF9F0A")
        )
    )

    static let errorInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#FF3B30"),
            dark:  UIColor(hex: "#FF453A")
        )
    )

    static let infoInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#5AC8FA"),
            dark:  UIColor(hex: "#64D2FF")
        )
    )

    static let separatorInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#C6C6C8"),
            dark:  UIColor(hex: "#38383A")
        )
    )

    static let fillInline = Color(
        uiColor: UIColor(
            light: UIColor(hex: "#F2F2F7"),
            dark:  UIColor(hex: "#2C2C2E")
        )
    )
}
