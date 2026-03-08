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
/// - `.finished`: Shows a summary card with the session results.
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
        .alert("Workout beenden?", isPresented: isConfirmingStop) {
            Button("Beenden", role: .destructive) {
                viewModel.confirmStop()
            }
            Button("Weiter", role: .cancel) {
                viewModel.cancelStop()
            }
        } message: {
            Text("Dein Fortschritt wird gespeichert.")
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

                    Text("Workout starten")
                        .font(AppTypography.roundedTitle)
                        .foregroundStyle(.white)

                    Text("Positioniere dich seitlich zur Kamera")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }

                Spacer()

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
                    .frame(height: AppSpacing.buttonHeightPrimary)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xxl)
            }
        }
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

    // MARK: - Finished Overlay

    private var finishedOverlay: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(AppColors.success)

                Text("Workout beendet!")
                    .font(AppTypography.roundedTitle)
                    .foregroundStyle(.white)

                summaryCard

                Button {
                    viewModel.resetForNewWorkout()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(icon: .arrowCounterclockwise)
                            .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                        Text("Neues Workout")
                            .font(AppTypography.buttonPrimary)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppSpacing.buttonHeightPrimary)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, AppSpacing.xl)
            }
            .padding(AppSpacing.xl)
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 0) {
            SummaryStatCell(
                value: "\(viewModel.pushUpCount)",
                label: "Push-Ups"
            )

            summaryDivider

            SummaryStatCell(
                value: WorkoutDurationFormatter.format(viewModel.sessionDuration),
                label: "Zeit"
            )

            if let score = viewModel.formScore {
                summaryDivider

                SummaryStatCell(
                    value: "\(Int(score * 100))%",
                    label: "Form",
                    valueColor: AppColors.formScoreColor(score)
                )
            }
        }
        .padding(AppSpacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        .padding(.horizontal, AppSpacing.xl)
    }

    private var summaryDivider: some View {
        Divider()
            .frame(height: 40)
            .background(.white.opacity(0.2))
    }

    // MARK: - Helpers

    private var isConfirmingStop: Binding<Bool> {
        Binding(
            get: { viewModel.phase == .confirmingStop },
            set: { if !$0 { viewModel.cancelStop() } }
        )
    }

}

// MARK: - SummaryStatCell

/// A single stat cell used in the workout summary card.
private struct SummaryStatCell: View {

    let value: String
    let label: String
    var valueColor: Color = .white

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            Text(value)
                .font(AppTypography.displayMedium)
                .foregroundStyle(valueColor)

            Text(label)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(.white.opacity(0.65))
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
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
