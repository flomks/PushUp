import SwiftUI

// MARK: - AppTypography

/// Centralised typography scale for the PushUp app.
///
/// All text styles are defined as static `Font` properties on `AppTypography`.
/// The scale follows Apple's Human Interface Guidelines and uses the SF Pro
/// typeface (system font) with Dynamic Type support where appropriate.
///
/// Usage:
/// ```swift
/// Text("Dashboard")
///     .font(AppTypography.title1)
///
/// Text("Push-Ups today")
///     .font(AppTypography.headline)
///
/// Text("Last session: 3 min ago")
///     .font(AppTypography.caption1)
/// ```
public enum AppTypography {

    // MARK: - Display

    /// Extra-large counter display -- used for the live push-up counter.
    /// Size: 96pt, Weight: Black, Design: Rounded
    public static let displayCounter = Font.system(
        size: 96,
        weight: .black,
        design: .rounded
    )

    /// Large display number -- used for summary screens (total push-ups, credits).
    /// Size: 64pt, Weight: Bold, Design: Rounded
    public static let displayLarge = Font.system(
        size: 64,
        weight: .bold,
        design: .rounded
    )

    /// Medium display number -- used for stat cards and prominent metrics.
    /// Size: 48pt, Weight: Bold, Design: Rounded
    public static let displayMedium = Font.system(
        size: 48,
        weight: .bold,
        design: .rounded
    )

    // MARK: - Title

    /// Title 1 -- primary screen title, used in navigation bars and hero sections.
    /// Size: 28pt, Weight: Bold
    public static let title1 = Font.system(size: 28, weight: .bold, design: .default)

    /// Title 2 -- secondary section title.
    /// Size: 22pt, Weight: Bold
    public static let title2 = Font.system(size: 22, weight: .bold, design: .default)

    /// Title 3 -- tertiary section title or card header.
    /// Size: 20pt, Weight: Semibold
    public static let title3 = Font.system(size: 20, weight: .semibold, design: .default)

    // MARK: - Headline

    /// Headline -- used for list section headers and prominent labels.
    /// Size: 17pt, Weight: Semibold
    public static let headline = Font.system(size: 17, weight: .semibold, design: .default)

    /// Subheadline -- used for secondary labels and supporting information.
    /// Size: 15pt, Weight: Regular
    public static let subheadline = Font.system(size: 15, weight: .regular, design: .default)

    /// Subheadline Semibold -- used for emphasized secondary labels.
    /// Size: 15pt, Weight: Semibold
    public static let subheadlineSemibold = Font.system(size: 15, weight: .semibold, design: .default)

    // MARK: - Body

    /// Body -- primary reading text, used for descriptions and content.
    /// Size: 17pt, Weight: Regular
    public static let body = Font.system(size: 17, weight: .regular, design: .default)

    /// Body Semibold -- emphasized body text.
    /// Size: 17pt, Weight: Semibold
    public static let bodySemibold = Font.system(size: 17, weight: .semibold, design: .default)

    /// Callout -- slightly smaller body text for secondary content areas.
    /// Size: 16pt, Weight: Regular
    public static let callout = Font.system(size: 16, weight: .regular, design: .default)

    // MARK: - Caption

    /// Caption 1 -- small supporting text, used for timestamps and metadata.
    /// Size: 12pt, Weight: Regular
    public static let caption1 = Font.system(size: 12, weight: .regular, design: .default)

    /// Caption 2 -- smallest text, used for legal copy and fine print.
    /// Size: 11pt, Weight: Regular
    public static let caption2 = Font.system(size: 11, weight: .regular, design: .default)

    /// Caption Semibold -- emphasized small text for badges and tags.
    /// Size: 12pt, Weight: Semibold
    public static let captionSemibold = Font.system(size: 12, weight: .semibold, design: .default)

    // MARK: - Monospaced (for timers and numeric displays)

    /// Monospaced body -- used for session timers and numeric counters.
    /// Size: 17pt, Weight: Regular, Design: Monospaced
    public static let monoBody = Font.system(size: 17, weight: .regular, design: .monospaced)

    /// Monospaced headline -- used for prominent timers (e.g. session duration).
    /// Size: 24pt, Weight: Semibold, Design: Monospaced
    public static let monoHeadline = Font.system(size: 24, weight: .semibold, design: .monospaced)

    /// Monospaced display -- used for the time-credit countdown display.
    /// Size: 48pt, Weight: Bold, Design: Monospaced
    public static let monoDisplay = Font.system(size: 48, weight: .bold, design: .monospaced)

    // MARK: - Rounded (for friendly / energetic contexts)

    /// Rounded headline -- used for phase labels and workout state indicators.
    /// Size: 17pt, Weight: Semibold, Design: Rounded
    public static let roundedHeadline = Font.system(size: 17, weight: .semibold, design: .rounded)

    /// Rounded title -- used for achievement titles and celebratory text.
    /// Size: 22pt, Weight: Bold, Design: Rounded
    public static let roundedTitle = Font.system(size: 22, weight: .bold, design: .rounded)

    // MARK: - Button Labels

    /// Primary button label.
    /// Size: 17pt, Weight: Semibold
    public static let buttonPrimary = Font.system(size: 17, weight: .semibold, design: .default)

    /// Secondary button label.
    /// Size: 15pt, Weight: Medium
    public static let buttonSecondary = Font.system(size: 15, weight: .medium, design: .default)

    /// Small button / chip label.
    /// Size: 13pt, Weight: Semibold
    public static let buttonSmall = Font.system(size: 13, weight: .semibold, design: .default)
}

// MARK: - Dynamic Type Variants

public extension AppTypography {

    /// Returns a Dynamic Type-aware version of the given style.
    /// Prefer these in accessibility-sensitive contexts.
    enum Dynamic {
        /// Equivalent to `AppTypography.title1` but scales with Dynamic Type.
        public static let title1 = Font.title.weight(.bold)

        /// Equivalent to `AppTypography.title2` but scales with Dynamic Type.
        public static let title2 = Font.title2.weight(.bold)

        /// Equivalent to `AppTypography.title3` but scales with Dynamic Type.
        public static let title3 = Font.title3.weight(.semibold)

        /// Equivalent to `AppTypography.headline` but scales with Dynamic Type.
        public static let headline = Font.headline

        /// Equivalent to `AppTypography.subheadline` but scales with Dynamic Type.
        public static let subheadline = Font.subheadline

        /// Equivalent to `AppTypography.body` but scales with Dynamic Type.
        public static let body = Font.body

        /// Equivalent to `AppTypography.callout` but scales with Dynamic Type.
        public static let callout = Font.callout

        /// Equivalent to `AppTypography.caption1` but scales with Dynamic Type.
        public static let caption1 = Font.caption

        /// Equivalent to `AppTypography.caption2` but scales with Dynamic Type.
        public static let caption2 = Font.caption2
    }
}

// MARK: - Text Style View Modifier

/// Convenience modifier that applies a predefined typography style and color.
///
/// Usage:
/// ```swift
/// Text("Push-Ups")
///     .textStyle(.headline, color: AppColors.textPrimary)
/// ```
public struct TextStyleModifier: ViewModifier {
    let font: Font
    let color: Color

    public func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundStyle(color)
    }
}

public extension View {
    /// Applies a typography style and optional color to a text view.
    func textStyle(_ font: Font, color: Color = AppColors.textPrimaryInline) -> some View {
        modifier(TextStyleModifier(font: font, color: color))
    }
}
