import SwiftUI

// MARK: - WorkoutControls

/// The bottom control bar shown during an active workout session.
///
/// Contains:
/// - **Stop button** (left): triggers the stop-confirmation flow.
/// - **Pose overlay toggle** (centre): shows/hides the skeleton overlay.
/// - **Camera flip button** (right): switches between front and back camera.
///
/// All buttons use `ScaleButtonStyle` and `.ultraThinMaterial` backgrounds
/// for consistent visual treatment over the camera feed.
///
/// **Usage**
/// ```swift
/// WorkoutControls(
///     showPoseOverlay: $viewModel.showPoseOverlay,
///     onStop: { viewModel.requestStop() },
///     onSwitchCamera: { viewModel.switchCamera() }
/// )
/// ```
struct WorkoutControls: View {

    // MARK: - Input

    @Binding var showPoseOverlay: Bool
    let onStop: () -> Void
    let onSwitchCamera: () -> Void

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Stop button
            Button(action: onStop) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 64, height: 64)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppColors.error)
                        .frame(width: 22, height: 22)
                }
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Workout stoppen")

            Spacer()

            // Pose overlay toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showPoseOverlay.toggle()
                }
            } label: {
                Image(systemName: showPoseOverlay ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: AppSpacing.iconSizeMedium, weight: .semibold))
                    .foregroundStyle(showPoseOverlay ? AppColors.primary : .white.opacity(0.6))
                    .frame(width: AppSpacing.minimumTapTarget, height: AppSpacing.minimumTapTarget)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel(showPoseOverlay ? "Pose-Overlay ausblenden" : "Pose-Overlay einblenden")

            Spacer()

            // Camera flip button
            Button(action: onSwitchCamera) {
                Image(icon: .cameraRotate)
                    .font(.system(size: AppSpacing.iconSizeMedium, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: AppSpacing.minimumTapTarget, height: AppSpacing.minimumTapTarget)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Kamera wechseln")
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - SessionTimerView

/// Displays the elapsed session time in `MM:SS` format.
///
/// Uses `AppTypography.monoHeadline` so the digits do not shift width as
/// seconds tick over.
struct SessionTimerView: View {

    let duration: TimeInterval

    var body: some View {
        Text(formattedDuration)
            .font(AppTypography.monoHeadline)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.3), value: duration)
    }

    private var formattedDuration: String {
        WorkoutDurationFormatter.format(duration)
    }
}

// MARK: - WarningBannerView

/// Shows the most actionable edge-case warning as a dismissible banner.
///
/// Only the first (highest-priority) warning is shown to avoid overwhelming
/// the user. The banner fades in/out smoothly as warnings change.
struct WarningBannerView: View {

    let warnings: [EdgeCaseWarning]

    var body: some View {
        if let warning = warnings.first {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                    .foregroundStyle(AppColors.warning)

                Text(warning.userMessage)
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - SoundToggleButton

/// A compact toggle button for enabling/disabling push-up sound effects.
struct SoundToggleButton: View {

    @Binding var isEnabled: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isEnabled.toggle()
            }
        } label: {
            Image(systemName: isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: AppSpacing.iconSizeSmall + 2, weight: .semibold))
                .foregroundStyle(isEnabled ? .white : .white.opacity(0.4))
                .frame(width: AppSpacing.minimumTapTarget, height: AppSpacing.minimumTapTarget)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(isEnabled ? "Sound deaktivieren" : "Sound aktivieren")
    }
}

// MARK: - WorkoutDurationFormatter

/// Shared duration formatting for the workout screen.
/// Formats a `TimeInterval` as `MM:SS`.
enum WorkoutDurationFormatter {

    static func format(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Workout Controls") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            WorkoutControls(
                showPoseOverlay: .constant(false),
                onStop: {},
                onSwitchCamera: {}
            )
        }
    }
}

#Preview("Session Timer") {
    ZStack {
        Color.black.ignoresSafeArea()
        SessionTimerView(duration: 125)
    }
}

#Preview("Warning Banner") {
    ZStack {
        Color.black.ignoresSafeArea()
        WarningBannerView(warnings: [.noPersonDetected])
    }
}
#endif
