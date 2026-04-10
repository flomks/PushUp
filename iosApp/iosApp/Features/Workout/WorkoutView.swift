import AVFoundation
import SwiftUI

// MARK: - WorkoutView

/// The main workout screen (Task 3.6).
///
/// **Layout**
/// ```
/// +-----------------------------------+
/// |  [Camera Preview - full screen]   |
/// |                                   |
/// |  [Warning Banner]    [Timer]      |  <- top HUD
/// |                                   |
/// |         [Push-Up Counter]         |  <- centre
/// |         [Form Score]              |
/// |                                   |
/// |  [Stop] [Overlay] [CamFlip]       |  <- bottom controls
/// +-----------------------------------+
/// ```
///
/// **States**
/// - `.idle`: Shows a "Start" button over the camera preview.
/// - `.active`: Shows the live counter, form score, timer, and controls.
/// - `.confirmingStop`: Shows a confirmation alert over the active overlay.
/// - `.finished`: Shows the full `WorkoutSummaryView` completion screen (Task 3.7).
///
/// **Acceptance criteria covered**
/// - Camera preview full-screen (`ignoresSafeArea`)
/// - Live push-up counter large and prominent (`displayCounter` 96pt)
/// - Form score colour-coded (green/yellow/red)
/// - Session timer in `MM:SS` format
/// - Pose overlay toggle (optional, via `WorkoutControls`)
/// - Stop confirmation alert
/// - Camera-flip button
/// - Screen stays on (`isIdleTimerDisabled` managed by `WorkoutViewModel`)
/// - Haptic feedback on every push-up (managed by `WorkoutViewModel`)
/// - Sound effect on every push-up (optional, managed by `WorkoutViewModel`)
struct WorkoutView: View {

    // MARK: - State

    @StateObject private var viewModel = WorkoutViewModel()

    /// Dismiss action for the fullScreenCover presentation.
    /// Used by the close button (idle) and "Back to Dashboard" (finished).
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        ZStack {
            // -- Camera Layer (always present) --------------------------------
            cameraLayer

            // -- Pose Overlay (toggleable, non-interactive) -------------------
            PoseOverlayView(
                pose: viewModel.currentPose,
                isVisible: viewModel.showPoseOverlay && viewModel.phase == .active
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // -- HUD Layer (phase-dependent) ----------------------------------
            switch viewModel.phase {
            case .idle:
                idleOverlay
            case .active, .confirmingStop:
                activeOverlay
            case .finished:
                finishedOverlay
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // Start the camera preview so the user can see themselves
            // before tapping "Start". The tracking pipeline (pose detection
            // + push-up counting) only starts when startWorkout() is called.
            if viewModel.phase == .idle {
                viewModel.startPreview()
            }
        }
        .onDisappear {
            // Only stop the camera preview when idle or finished.
            // If a workout is active, leave it running -- the user may
            // have accidentally swiped to another tab. They must explicitly
            // stop via the stop button + confirmation dialog.
            if viewModel.phase == .idle || viewModel.phase == .finished {
                viewModel.stopPreview()
            }
        }
        // Dismiss when an empty session (0 push-ups) is discarded.
        .onChange(of: viewModel.emptySessionDiscarded) {
            if viewModel.emptySessionDiscarded {
                dismiss()
            }
        }
        // Stop-confirmation alert
        .alert("End Workout?", isPresented: isConfirmingStop) {
            Button("End", role: .destructive) {
                viewModel.confirmStop()
            }
            Button("Continue", role: .cancel) {
                viewModel.cancelStop()
            }
        } message: {
            Text("Your progress will be saved.")
        }
    }

    // MARK: - Camera Layer

    @ViewBuilder
    private var cameraLayer: some View {
        switch viewModel.cameraState {
        case .idle, .running, .stopped:
            WorkoutCameraPreview(previewLayer: viewModel.previewLayer)
                .ignoresSafeArea()
        case .error(let error):
            CameraUnavailableView(error: error)
                .ignoresSafeArea()
        }
    }

    // MARK: - Idle Overlay

    private var idleOverlay: some View {
        GeometryReader { geo in
            let topInset = max(geo.safeAreaInsets.top, AppSpacing.xxl)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()

                VStack(spacing: AppSpacing.xl) {
                    Spacer()

                    VStack(spacing: AppSpacing.sm) {
                        Image(icon: .figureStrengthTraining)
                            .font(.system(size: 72, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolRenderingMode(.hierarchical)

                        Text("Push-Ups")
                            .font(AppTypography.roundedTitle)
                            .foregroundStyle(.white)

                        Text("Position yourself from the side or front")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.xl)
                    }

                    Spacer()

                    startButton(bottomInset: geo.safeAreaInsets.bottom)
                }

                // Back button -- positioned below Dynamic Island / notch
                backButton
                    .padding(.top, topInset + AppSpacing.sm)
                    .padding(.leading, AppSpacing.md)
            }
        }
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button {
            viewModel.stopPreview()
            dismiss()
        } label: {
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                Text("Back")
                    .font(AppTypography.subheadlineSemibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.sm)
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("Back to workout selection")
    }

    private func startButton(bottomInset: CGFloat) -> some View {
        // bottomInset = home indicator safe area (~34pt Face ID, 0pt Home button).
        // Presented as fullScreenCover so no tab bar offset needed.
        Button {
            viewModel.startWorkout()
        } label: {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: WorkoutType.pushUps.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(icon: .playFill)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Workout")
                        .font(AppTypography.buttonPrimary)
                        .foregroundStyle(DashboardWidgetChrome.labelPrimary)

                    Text("Auto-detects side and front view")
                        .font(AppTypography.caption1)
                        .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                }

                Spacer()

                Image(icon: .chevronRight)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DashboardWidgetChrome.labelMuted)
            }
            .padding(.horizontal, DashboardWidgetChrome.padding)
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .dashboardWidgetChrome(cornerRadius: AppSpacing.cornerRadiusLarge)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [WorkoutType.pushUps.accentColor.opacity(0.4), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, AppSpacing.xl)
        .padding(.bottom, bottomInset + AppSpacing.lg)
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Active Overlay

    private var activeOverlay: some View {
        GeometryReader { geo in
            let topInset = max(geo.safeAreaInsets.top, AppSpacing.xxl)

            VStack(spacing: 0) {
                topHUD
                    .padding(.top, topInset + AppSpacing.sm)
                    .padding(.horizontal, AppSpacing.md)

                Spacer()

                VStack(spacing: AppSpacing.sm) {
                    LiveCounterView(count: viewModel.pushUpCount)
                    trackingViewIndicator
                    FormScoreIndicator(
                        score: viewModel.formScore,
                        supportsFormScoring: viewModel.trackingView != .front
                    )
                }
                .padding(.bottom, AppSpacing.lg)

                Spacer()

                WorkoutControls(
                    showPoseOverlay: $viewModel.showPoseOverlay,
                    onStop: { viewModel.requestStop() },
                    onSwitchCamera: { viewModel.switchCamera() }
                )
                .padding(.bottom, max(geo.safeAreaInsets.bottom, AppSpacing.md))
            }
        }
    }

    // MARK: - Top HUD

    private var topHUD: some View {
        HStack(alignment: .top) {
            WarningBannerView(warnings: viewModel.activeWarnings)
                .animation(.easeInOut(duration: 0.3), value: viewModel.activeWarnings)

            Spacer()

            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                SessionTimerView(duration: viewModel.sessionDuration)
                SoundToggleButton(isEnabled: $viewModel.soundEnabled)
            }
        }
    }

    private var trackingViewIndicator: some View {
        HStack(spacing: AppSpacing.xs) {
            Circle()
                .fill(viewModel.trackingView == .front ? AppColors.info : AppColors.success)
                .frame(width: 8, height: 8)

            Text(viewModel.trackingView.displayName)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(.white)

            if viewModel.trackingView == .front {
                Text("Count only")
                    .font(AppTypography.caption1)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Finished Overlay (Task 3.7)

    /// Full-screen workout completion screen.
    ///
    /// Replaces the previous inline summary card with the rich
    /// `WorkoutSummaryView` that includes animated counters, confetti,
    /// share functionality, and a "Back" button.
    ///
    /// The `onDashboard` callback dismisses the fullScreenCover so the
    /// user returns to the workout selection hub. The view model is reset
    /// first so the next presentation starts fresh.
    private var finishedOverlay: some View {
        WorkoutSummaryView(
            pushUpCount: viewModel.pushUpCount,
            durationSeconds: Int(viewModel.sessionDuration),
            earnedMinutes: viewModel.earnedMinutes,
            qualityScore: viewModel.formScore,
            comparisonPercent: viewModel.comparisonPercent,
            isNewRecord: viewModel.isNewRecord,
            onDashboard: {
                viewModel.resetForNewWorkout()
                dismiss()
            }
        )
        .ignoresSafeArea()
    }

    // MARK: - Helpers

    private var isConfirmingStop: Binding<Bool> {
        Binding(
            get: { viewModel.phase == .confirmingStop },
            set: { if !$0 { viewModel.cancelStop() } }
        )
    }

}

// MARK: - WorkoutCameraPreview

/// A lightweight SwiftUI wrapper that displays the tracking manager's
/// `AVCaptureVideoPreviewLayer` without exposing the `CameraManager`.
///
/// This avoids the need for `WorkoutView` to hold a reference to
/// `CameraManager` directly.
struct WorkoutCameraPreview: UIViewRepresentable {

    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.setPreviewLayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // The preview layer is permanently attached; frame updates happen
        // in `layoutSubviews`. Nothing to do here.
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Workout - Idle") {
    WorkoutView()
}
#endif
