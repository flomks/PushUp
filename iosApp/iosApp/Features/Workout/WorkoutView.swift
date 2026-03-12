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
        // Give the tab bar a solid material background so it is clearly
        // visible over the camera feed. Without this the tab bar is
        // transparent and blends into the camera image.
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.xl) {
                Spacer()

                VStack(spacing: AppSpacing.sm) {
                    Image(icon: .figureStrengthTraining)
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)

                    Text("Start Workout")
                        .font(AppTypography.roundedTitle)
                        .foregroundStyle(.white)

                    Text("Position yourself sideways to the camera")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }

                Spacer()

                // Start button sits above the tab bar.
                // The view uses ignoresSafeArea() so the system safe area
                // inset does not account for the tab bar (49pt). We read
                // the bottom safe area for the home indicator and add the
                // standard tab bar height on top of it.
                startButton
            }
        }
    }

    private var startButton: some View {
        Button {
            viewModel.startWorkout()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(icon: .playFill)
                    .font(.system(size: AppSpacing.iconSizeStandard, weight: .bold))
                Text("Start")
                    .font(AppTypography.buttonPrimary)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.buttonHeightPrimary + 8)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, AppSpacing.xl)
        // 49pt tab bar + 16pt gap above it + home-indicator safe area
        .padding(.bottom, 49 + AppSpacing.md)
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Active Overlay

    private var activeOverlay: some View {
        VStack(spacing: 0) {
            topHUD
                .padding(.top, AppSpacing.xxl)
                .padding(.horizontal, AppSpacing.md)

            Spacer()

            VStack(spacing: AppSpacing.sm) {
                LiveCounterView(count: viewModel.pushUpCount)
                FormScoreIndicator(score: viewModel.formScore)
            }
            .padding(.bottom, AppSpacing.lg)

            Spacer()

            WorkoutControls(
                showPoseOverlay: $viewModel.showPoseOverlay,
                onStop: { viewModel.requestStop() },
                onSwitchCamera: { viewModel.switchCamera() }
            )
            .padding(.bottom, AppSpacing.xl)
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

    // MARK: - Finished Overlay (Task 3.7)

    /// Full-screen workout completion screen.
    ///
    /// Replaces the previous inline summary card with the rich
    /// `WorkoutSummaryView` that includes animated counters, confetti,
    /// share functionality, and a "Zurueck zum Dashboard" button.
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
