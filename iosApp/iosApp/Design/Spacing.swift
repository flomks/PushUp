import SwiftUI

// MARK: - AppSpacing

/// Centralised spacing constants on a **4-point grid**.
///
/// Use these constants instead of raw numeric literals to ensure consistent
/// layout across all screens.
///
/// Usage:
/// ```swift
/// VStack(spacing: AppSpacing.md) {
///     Text("Title")
///     Text("Subtitle")
/// }
/// .padding(.horizontal, AppSpacing.screenHorizontal)
/// ```
enum AppSpacing {

    // MARK: - Base Grid (4pt increments)

    /// 4pt -- minimum spacing for tight element groupings.
    static let xxs: CGFloat = 4

    /// 8pt -- small spacing between related elements within a component.
    static let xs: CGFloat = 8

    /// 12pt -- compact list rows and icon gaps.
    static let sm: CGFloat = 12

    /// 16pt -- standard padding inside cards and cells.
    static let md: CGFloat = 16

    /// 24pt -- spacing between distinct sections within a screen.
    static let lg: CGFloat = 24

    /// 32pt -- major section separations.
    static let xl: CGFloat = 32

    /// 48pt -- hero sections and top-level padding.
    static let xxl: CGFloat = 48

    // MARK: - Semantic Aliases

    /// Standard horizontal screen edge padding (16pt).
    static let screenHorizontal: CGFloat = md

    /// Standard vertical screen top padding (24pt).
    static let screenVerticalTop: CGFloat = lg

    /// Standard vertical screen bottom padding (32pt).
    static let screenVerticalBottom: CGFloat = xl

    /// Padding inside a card component (16pt).
    static let cardPadding: CGFloat = md

    /// Padding inside a compact stat card (12pt).
    static let statCardPadding: CGFloat = sm

    /// Vertical spacing between list rows (8pt).
    static let listRowSpacing: CGFloat = xs

    /// Spacing between a label and its icon (8pt).
    static let iconLabelGap: CGFloat = xs

    /// Spacing between stacked buttons (12pt).
    static let buttonStackSpacing: CGFloat = sm

    // MARK: - Corner Radii

    /// Cards and containers (16pt).
    static let cornerRadiusCard: CGFloat = md

    /// Buttons (12pt).
    static let cornerRadiusButton: CGFloat = sm

    /// Small chips and badges (8pt).
    static let cornerRadiusChip: CGFloat = xs

    /// Large hero containers (24pt).
    static let cornerRadiusLarge: CGFloat = lg

    // MARK: - Component Heights

    /// Primary button height (52pt).
    static let buttonHeightPrimary: CGFloat = 52

    /// Secondary / compact button height (44pt).
    static let buttonHeightSecondary: CGFloat = 44

    /// Small chip / tag button height (32pt).
    static let buttonHeightSmall: CGFloat = 32

    /// Minimum tappable area per HIG (44pt).
    static let minimumTapTarget: CGFloat = 44

    // MARK: - Icon Sizes

    /// Small icon (16pt).
    static let iconSizeSmall: CGFloat = 16

    /// Standard icon (20pt).
    static let iconSizeStandard: CGFloat = 20

    /// Medium icon (24pt).
    static let iconSizeMedium: CGFloat = 24

    /// Large icon (32pt).
    static let iconSizeLarge: CGFloat = 32

    /// Extra-large icon (48pt).
    static let iconSizeXL: CGFloat = 48
}

// MARK: - EdgeInsets Helpers

extension AppSpacing {

    /// Standard screen content insets.
    static var screenInsets: EdgeInsets {
        EdgeInsets(
            top: screenVerticalTop,
            leading: screenHorizontal,
            bottom: screenVerticalBottom,
            trailing: screenHorizontal
        )
    }

    /// Card content insets (16pt all sides).
    static var cardInsets: EdgeInsets {
        EdgeInsets(
            top: cardPadding, leading: cardPadding,
            bottom: cardPadding, trailing: cardPadding
        )
    }
}

// MARK: - View Padding Helpers

extension View {

    /// Applies standard horizontal screen padding (16pt each side).
    func screenHorizontalPadding() -> some View {
        padding(.horizontal, AppSpacing.screenHorizontal)
    }
}
