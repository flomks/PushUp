import SwiftUI

// MARK: - AppSpacing

/// Centralised spacing constants for the PushUp app.
///
/// All spacing values follow a **4-point grid system**. Use these constants
/// instead of raw numeric literals to ensure consistent layout across all
/// screens and to make future spacing adjustments trivial.
///
/// Usage:
/// ```swift
/// VStack(spacing: AppSpacing.md) {
///     Text("Title")
///     Text("Subtitle")
/// }
/// .padding(.horizontal, AppSpacing.screenHorizontal)
/// ```
public enum AppSpacing {

    // MARK: - Base Grid (4pt increments)

    /// 4pt -- minimum spacing, used for tight element groupings.
    public static let xxs: CGFloat = 4

    /// 8pt -- small spacing, used between related elements within a component.
    public static let xs: CGFloat = 8

    /// 12pt -- small-medium spacing, used for compact list rows and icon gaps.
    public static let sm: CGFloat = 12

    /// 16pt -- medium spacing, used for standard padding inside cards and cells.
    public static let md: CGFloat = 16

    /// 24pt -- large spacing, used between distinct sections within a screen.
    public static let lg: CGFloat = 24

    /// 32pt -- extra-large spacing, used for major section separations.
    public static let xl: CGFloat = 32

    /// 48pt -- 2x-large spacing, used for hero sections and top-level padding.
    public static let xxl: CGFloat = 48

    // MARK: - Semantic Aliases

    /// Standard horizontal screen edge padding (16pt).
    public static let screenHorizontal: CGFloat = md

    /// Standard vertical screen top padding (24pt).
    public static let screenVerticalTop: CGFloat = lg

    /// Standard vertical screen bottom padding (32pt).
    public static let screenVerticalBottom: CGFloat = xl

    /// Padding inside a card component (16pt horizontal, 16pt vertical).
    public static let cardPadding: CGFloat = md

    /// Padding inside a compact stat card (12pt).
    public static let statCardPadding: CGFloat = sm

    /// Vertical spacing between list rows (8pt).
    public static let listRowSpacing: CGFloat = xs

    /// Spacing between a label and its icon (8pt).
    public static let iconLabelGap: CGFloat = xs

    /// Spacing between stacked buttons (12pt).
    public static let buttonStackSpacing: CGFloat = sm

    /// Corner radius for cards and containers (16pt).
    public static let cornerRadiusCard: CGFloat = md

    /// Corner radius for buttons (12pt).
    public static let cornerRadiusButton: CGFloat = sm

    /// Corner radius for small chips and badges (8pt).
    public static let cornerRadiusChip: CGFloat = xs

    /// Corner radius for large hero containers (24pt).
    public static let cornerRadiusLarge: CGFloat = lg

    // MARK: - Component Heights

    /// Standard height for primary buttons (52pt).
    public static let buttonHeightPrimary: CGFloat = 52

    /// Standard height for secondary / compact buttons (44pt).
    public static let buttonHeightSecondary: CGFloat = 44

    /// Standard height for small chip / tag buttons (32pt).
    public static let buttonHeightSmall: CGFloat = 32

    /// Minimum tappable area per HIG (44pt).
    public static let minimumTapTarget: CGFloat = 44

    // MARK: - Icon Sizes

    /// Small icon size (16pt).
    public static let iconSizeSmall: CGFloat = 16

    /// Standard icon size (20pt).
    public static let iconSizeStandard: CGFloat = 20

    /// Medium icon size (24pt).
    public static let iconSizeMedium: CGFloat = 24

    /// Large icon size (32pt).
    public static let iconSizeLarge: CGFloat = 32

    /// Extra-large icon size (48pt).
    public static let iconSizeXL: CGFloat = 48
}

// MARK: - EdgeInsets Helpers

public extension AppSpacing {

    /// Standard screen content insets (horizontal: 16pt, vertical: 24pt top / 32pt bottom).
    static var screenInsets: EdgeInsets {
        EdgeInsets(
            top: screenVerticalTop,
            leading: screenHorizontal,
            bottom: screenVerticalBottom,
            trailing: screenHorizontal
        )
    }

    /// Card content insets (all sides: 16pt).
    static var cardInsets: EdgeInsets {
        EdgeInsets(
            top: cardPadding,
            leading: cardPadding,
            bottom: cardPadding,
            trailing: cardPadding
        )
    }

    /// Stat card content insets (all sides: 12pt).
    static var statCardInsets: EdgeInsets {
        EdgeInsets(
            top: statCardPadding,
            leading: statCardPadding,
            bottom: statCardPadding,
            trailing: statCardPadding
        )
    }
}

// MARK: - View Padding Helpers

public extension View {

    /// Applies standard horizontal screen padding (16pt on each side).
    func screenHorizontalPadding() -> some View {
        padding(.horizontal, AppSpacing.screenHorizontal)
    }

    /// Applies standard card padding (16pt on all sides).
    func cardPadding() -> some View {
        padding(AppSpacing.cardPadding)
    }

    /// Applies standard stat card padding (12pt on all sides).
    func statCardPadding() -> some View {
        padding(AppSpacing.statCardPadding)
    }
}
