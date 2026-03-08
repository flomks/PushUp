import SwiftUI

// MARK: - PrimaryButton

/// A full-width, high-emphasis button for the primary action on a screen.
///
/// Usage:
/// ```swift
/// PrimaryButton("Workout starten", icon: "figure.run") {
///     viewModel.startWorkout()
/// }
///
/// // Disabled state
/// PrimaryButton("Workout starten") {
///     viewModel.startWorkout()
/// }
/// .disabled(true)
///
/// // Loading state
/// PrimaryButton("Speichern", isLoading: true) {}
/// ```
public struct PrimaryButton: View {

    // MARK: Properties

    private let title: String
    private let icon: String?
    private let isLoading: Bool
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    // MARK: Init

    public init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }

    // MARK: Body

    public var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColors.textOnPrimary)
                        .scaleEffect(0.85)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                }

                Text(title)
                    .font(AppTypography.buttonPrimary)
            }
            .foregroundStyle(AppColors.textOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.buttonHeightPrimary)
            .background(backgroundGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .disabled(isLoading)
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: Private

    private var backgroundGradient: some ShapeStyle {
        if isEnabled {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        AppColors.primaryInline,
                        AppColors.primaryInline.opacity(0.85)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(AppColors.fillInline)
        }
    }
}

// MARK: - SecondaryButton

/// A full-width, medium-emphasis button for secondary actions.
///
/// Renders as an outlined button with the primary color border and label.
///
/// Usage:
/// ```swift
/// SecondaryButton("Abbrechen") {
///     dismiss()
/// }
///
/// SecondaryButton("Details anzeigen", icon: "info.circle") {
///     showDetails = true
/// }
/// ```
public struct SecondaryButton: View {

    // MARK: Properties

    private let title: String
    private let icon: String?
    private let isLoading: Bool
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    // MARK: Init

    public init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }

    // MARK: Body

    public var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColors.primaryInline)
                        .scaleEffect(0.85)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: AppSpacing.iconSizeStandard, weight: .medium))
                }

                Text(title)
                    .font(AppTypography.buttonSecondary)
            }
            .foregroundStyle(isEnabled ? AppColors.primaryInline : AppColors.textTertiaryInline)
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.buttonHeightSecondary)
            .background(AppColors.backgroundSecondaryInline)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                    .strokeBorder(
                        isEnabled ? AppColors.primaryInline : AppColors.separatorInline,
                        lineWidth: 1.5
                    )
            )
        }
        .disabled(isLoading)
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - DestructiveButton

/// A full-width button for destructive / irreversible actions (e.g. delete, logout).
///
/// Usage:
/// ```swift
/// DestructiveButton("Workout loeschen") {
///     viewModel.deleteWorkout()
/// }
/// ```
public struct DestructiveButton: View {

    private let title: String
    private let icon: String?
    private let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(role: .destructive, action: action) {
            HStack(spacing: AppSpacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: AppSpacing.iconSizeStandard, weight: .medium))
                }
                Text(title)
                    .font(AppTypography.buttonSecondary)
            }
            .foregroundStyle(AppColors.errorInline)
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.buttonHeightSecondary)
            .background(AppColors.errorInline.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - IconButton

/// A compact, circular icon-only button.
///
/// Usage:
/// ```swift
/// IconButton("arrow.counterclockwise", accessibilityLabel: "Reset") {
///     viewModel.reset()
/// }
///
/// // With tint override
/// IconButton("camera.rotate", tint: .white) {
///     cameraManager.flipCamera()
/// }
/// ```
public struct IconButton: View {

    private let systemName: String
    private let accessibilityLabel: String
    private let size: CGFloat
    private let tint: Color?
    private let action: () -> Void

    public init(
        _ systemName: String,
        accessibilityLabel: String = "",
        size: CGFloat = AppSpacing.iconSizeMedium,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.size = size
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint ?? AppColors.primaryInline)
                .frame(
                    width: max(AppSpacing.minimumTapTarget, size + AppSpacing.md),
                    height: max(AppSpacing.minimumTapTarget, size + AppSpacing.md)
                )
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - ChipButton

/// A small, pill-shaped toggle chip used for filter selections.
///
/// Usage:
/// ```swift
/// ChipButton("Diese Woche", isSelected: selectedFilter == .week) {
///     selectedFilter = .week
/// }
/// ```
public struct ChipButton: View {

    private let title: String
    private let icon: String?
    private let isSelected: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xxs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                }
                Text(title)
                    .font(AppTypography.buttonSmall)
            }
            .foregroundStyle(isSelected ? AppColors.textOnPrimary : AppColors.primaryInline)
            .padding(.horizontal, AppSpacing.sm)
            .frame(height: AppSpacing.buttonHeightSmall)
            .background(
                isSelected ? AppColors.primaryInline : AppColors.primaryInline.opacity(0.1),
                in: Capsule()
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - ScaleButtonStyle

/// A button style that applies a subtle scale-down animation on press.
/// Used by all design-system buttons to provide consistent tactile feedback.
public struct ScaleButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Buttons") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {

            Group {
                Text("Primary Button")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondaryInline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryButton("Workout starten", icon: "figure.run") {}
                PrimaryButton("Laden...", isLoading: true) {}
                PrimaryButton("Deaktiviert") {}.disabled(true)
            }

            Divider()

            Group {
                Text("Secondary Button")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondaryInline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SecondaryButton("Details anzeigen", icon: "info.circle") {}
                SecondaryButton("Laden...", isLoading: true) {}
                SecondaryButton("Deaktiviert") {}.disabled(true)
            }

            Divider()

            Group {
                Text("Destructive Button")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondaryInline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                DestructiveButton("Workout loeschen", icon: "trash") {}
            }

            Divider()

            Group {
                Text("Icon Buttons")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondaryInline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: AppSpacing.md) {
                    IconButton("arrow.counterclockwise", accessibilityLabel: "Reset") {}
                    IconButton("camera.rotate", accessibilityLabel: "Kamera wechseln") {}
                    IconButton("figure.arms.open", accessibilityLabel: "Overlay") {}
                }
            }

            Divider()

            Group {
                Text("Chip Buttons")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondaryInline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: AppSpacing.xs) {
                    ChipButton("Heute", isSelected: true) {}
                    ChipButton("Woche") {}
                    ChipButton("Monat") {}
                    ChipButton("Gesamt") {}
                }
            }
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimaryInline)
}
#endif
