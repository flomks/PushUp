import SwiftUI

// MARK: - PrimaryButton

/// Full-width, high-emphasis button for the primary action on a screen.
///
/// Usage:
/// ```swift
/// PrimaryButton("Workout starten", icon: .figureRun) {
///     viewModel.startWorkout()
/// }
///
/// PrimaryButton("Speichern", isLoading: true) {}
/// ```
struct PrimaryButton: View {

    private let title: String
    private let icon: AppIcon?
    private let isLoading: Bool
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(
        _ title: String,
        icon: AppIcon? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColors.textOnPrimary)
                        .scaleEffect(0.85)
                } else if let icon {
                    Image(systemName: icon.rawValue)
                        .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                }

                Text(title)
                    .font(AppTypography.buttonPrimary)
            }
            .foregroundStyle(AppColors.textOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.buttonHeightPrimary)
            .background(
                isEnabled
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [AppColors.primary, AppColors.primary.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(AppColors.fill)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .disabled(isLoading)
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - SecondaryButton

/// Full-width, medium-emphasis outlined button for secondary actions.
///
/// Usage:
/// ```swift
/// SecondaryButton("Abbrechen") { dismiss() }
/// SecondaryButton("Details", icon: .infoCircle) { showDetails = true }
/// ```
struct SecondaryButton: View {

    private let title: String
    private let icon: AppIcon?
    private let isLoading: Bool
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(
        _ title: String,
        icon: AppIcon? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColors.primary)
                        .scaleEffect(0.85)
                } else if let icon {
                    Image(systemName: icon.rawValue)
                        .font(.system(size: AppSpacing.iconSizeStandard, weight: .medium))
                }

                Text(title)
                    .font(AppTypography.buttonSecondary)
            }
            .foregroundStyle(isEnabled ? AppColors.primary : AppColors.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.buttonHeightSecondary)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                    .strokeBorder(
                        isEnabled ? AppColors.primary : AppColors.separator,
                        lineWidth: 1.5
                    )
            )
        }
        .disabled(isLoading)
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - DestructiveButton

/// Full-width button for destructive / irreversible actions.
///
/// Usage:
/// ```swift
/// DestructiveButton("Workout loeschen", icon: .trash) {
///     viewModel.deleteWorkout()
/// }
/// ```
struct DestructiveButton: View {

    private let title: String
    private let icon: AppIcon?
    private let action: () -> Void

    init(
        _ title: String,
        icon: AppIcon? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(role: .destructive, action: action) {
            HStack(spacing: AppSpacing.xs) {
                if let icon {
                    Image(systemName: icon.rawValue)
                        .font(.system(size: AppSpacing.iconSizeStandard, weight: .medium))
                }
                Text(title)
                    .font(AppTypography.buttonSecondary)
            }
            .foregroundStyle(AppColors.error)
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.buttonHeightSecondary)
            .background(AppColors.error.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - IconButton

/// Compact, circular icon-only button with material background.
///
/// Usage:
/// ```swift
/// IconButton(.arrowCounterclockwise, label: "Reset") {
///     viewModel.reset()
/// }
/// ```
struct IconButton: View {

    private let icon: AppIcon
    private let label: String
    private let size: CGFloat
    private let tint: Color?
    private let action: () -> Void

    init(
        _ icon: AppIcon,
        label: String,
        size: CGFloat = AppSpacing.iconSizeMedium,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.size = size
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon.rawValue)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint ?? AppColors.primary)
                .frame(
                    width: max(AppSpacing.minimumTapTarget, size + AppSpacing.md),
                    height: max(AppSpacing.minimumTapTarget, size + AppSpacing.md)
                )
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - ChipButton

/// Small, pill-shaped toggle chip for filter selections.
///
/// Usage:
/// ```swift
/// ChipButton("Diese Woche", isSelected: filter == .week) {
///     filter = .week
/// }
/// ```
struct ChipButton: View {

    private let title: String
    private let icon: AppIcon?
    private let isSelected: Bool
    private let action: () -> Void

    init(
        _ title: String,
        icon: AppIcon? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xxs) {
                if let icon {
                    Image(systemName: icon.rawValue)
                        .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                }
                Text(title)
                    .font(AppTypography.buttonSmall)
            }
            .foregroundStyle(isSelected ? AppColors.textOnPrimary : AppColors.primary)
            .padding(.horizontal, AppSpacing.sm)
            .frame(height: AppSpacing.buttonHeightSmall)
            .background(
                isSelected ? AppColors.primary : AppColors.primary.opacity(0.1),
                in: Capsule()
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(title)
    }
}

// MARK: - ScaleButtonStyle

/// Subtle scale-down animation on press for consistent tactile feedback.
///
/// Uses a `DragGesture(minimumDistance: 0)` overlay so the press state is
/// recognised immediately even when the button lives inside a `ScrollView`
/// (which normally delays tap recognition by ~150 ms to distinguish taps
/// from scroll gestures).
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.10), value: configuration.isPressed)
            // Allow the button to receive the press immediately in scroll views
            .contentShape(Rectangle())
    }
}

// MARK: - InstantPressButtonStyle

/// A wrapper that makes any button inside a `ScrollView` respond to presses
/// without the system's built-in scroll-disambiguation delay.
///
/// Apply this to the outermost container of a button that lives in a scroll
/// view when you need the scale / highlight feedback to appear instantly.
struct InstantPressButtonStyle: ButtonStyle {
    @State private var isPressed = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.10), value: isPressed)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed { isPressed = true }
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Buttons") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {

            Group {
                Text("Primary Button").font(AppTypography.captionSemibold)
                PrimaryButton("Start Workout", icon: .figureRun) {}
                PrimaryButton("Loading...", isLoading: true) {}
                PrimaryButton("Disabled") {}.disabled(true)
            }

            Divider()

            Group {
                Text("Secondary Button").font(AppTypography.captionSemibold)
                SecondaryButton("Show Details", icon: .infoCircle) {}
                SecondaryButton("Loading...", isLoading: true) {}
                SecondaryButton("Disabled") {}.disabled(true)
            }

            Divider()

            Group {
                Text("Destructive Button").font(AppTypography.captionSemibold)
                DestructiveButton("Delete Workout", icon: .trash) {}
            }

            Divider()

            Group {
                Text("Icon Buttons").font(AppTypography.captionSemibold)
                HStack(spacing: AppSpacing.md) {
                    IconButton(.arrowCounterclockwise, label: "Reset") {}
                    IconButton(.cameraRotate, label: "Switch Camera") {}
                    IconButton(.figureArmsOpen, label: "Overlay") {}
                }
            }

            Divider()

            Group {
                Text("Chip Buttons").font(AppTypography.captionSemibold)
                HStack(spacing: AppSpacing.xs) {
                    ChipButton("Today", isSelected: true) {}
                    ChipButton("Week") {}
                    ChipButton("Month") {}
                    ChipButton("All") {}
                }
            }
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimary)
}
#endif
