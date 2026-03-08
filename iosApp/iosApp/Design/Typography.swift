import SwiftUI

// MARK: - AppTypography

/// Centralised typography scale for the PushUp app.
///
/// Standard text styles use SwiftUI's built-in `TextStyle` system so they
/// automatically scale with Dynamic Type. Fixed-size fonts are only used for
/// display counters and numeric readouts where scaling would break layout.
///
/// Usage:
/// ```swift
/// Text("Dashboard")
///     .font(AppTypography.title1)
///
/// Text("42")
///     .font(AppTypography.displayCounter)
/// ```
enum AppTypography {

    // MARK: - Display (fixed size -- layout-critical)

    /// Extra-large counter -- live push-up counter overlay.
    /// 96pt Black Rounded. Does NOT scale with Dynamic Type.
    static let displayCounter = Font.system(
        size: 96, weight: .black, design: .rounded
    )

    /// Large display number -- summary screens (total push-ups, credits).
    /// 56pt Bold Rounded. Does NOT scale with Dynamic Type.
    static let displayLarge = Font.system(
        size: 56, weight: .bold, design: .rounded
    )

    /// Medium display number -- stat cards and prominent metrics.
    /// 34pt Bold Rounded. Does NOT scale with Dynamic Type.
    static let displayMedium = Font.system(
        size: 34, weight: .bold, design: .rounded
    )

    // MARK: - Title (scales with Dynamic Type)

    /// Primary screen title -- navigation bars and hero sections.
    static let title1: Font = .title.weight(.bold)

    /// Secondary section title.
    static let title2: Font = .title2.weight(.bold)

    /// Tertiary section title or card header.
    static let title3: Font = .title3.weight(.semibold)

    // MARK: - Headline (scales with Dynamic Type)

    /// List section headers and prominent labels.
    static let headline: Font = .headline

    /// Secondary labels and supporting information.
    static let subheadline: Font = .subheadline

    /// Emphasized secondary labels.
    static let subheadlineSemibold: Font = .subheadline.weight(.semibold)

    // MARK: - Body (scales with Dynamic Type)

    /// Primary reading text -- descriptions and content.
    static let body: Font = .body

    /// Emphasized body text.
    static let bodySemibold: Font = .body.weight(.semibold)

    /// Slightly smaller body text for secondary content areas.
    static let callout: Font = .callout

    // MARK: - Caption (scales with Dynamic Type)

    /// Small supporting text -- timestamps and metadata.
    static let caption1: Font = .caption

    /// Smallest text -- legal copy and fine print.
    static let caption2: Font = .caption2

    /// Emphasized small text for badges and tags.
    static let captionSemibold: Font = .caption.weight(.semibold)

    // MARK: - Monospaced (fixed size -- numeric readouts)

    /// Monospaced body -- session timers and numeric counters.
    static let monoBody = Font.system(
        size: 17, weight: .regular, design: .monospaced
    )

    /// Monospaced headline -- prominent timers (session duration).
    static let monoHeadline = Font.system(
        size: 24, weight: .semibold, design: .monospaced
    )

    /// Monospaced display -- time-credit countdown.
    static let monoDisplay = Font.system(
        size: 40, weight: .bold, design: .monospaced
    )

    // MARK: - Rounded (friendly / energetic contexts)

    /// Rounded headline -- phase labels and workout state indicators.
    static let roundedHeadline = Font.system(
        size: 17, weight: .semibold, design: .rounded
    )

    /// Rounded title -- achievement titles and celebratory text.
    static let roundedTitle = Font.system(
        size: 22, weight: .bold, design: .rounded
    )

    // MARK: - Button Labels (scales with Dynamic Type)

    /// Primary button label.
    static let buttonPrimary: Font = .body.weight(.semibold)

    /// Secondary button label.
    static let buttonSecondary: Font = .subheadline.weight(.medium)

    /// Small button / chip label.
    static let buttonSmall: Font = .caption.weight(.semibold)
}

// MARK: - Text Style View Modifier

/// Convenience modifier that applies a typography style and color in one call.
///
/// Usage:
/// ```swift
/// Text("Push-Ups")
///     .textStyle(AppTypography.headline, color: AppColors.textPrimary)
/// ```
struct TextStyleModifier: ViewModifier {
    let font: Font
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundStyle(color)
    }
}

extension View {
    /// Applies a typography style and color to a view.
    func textStyle(_ font: Font, color: Color = AppColors.textPrimary) -> some View {
        modifier(TextStyleModifier(font: font, color: color))
    }
}
