import SwiftUI

// MARK: - WorkoutView

/// The main workout screen (Task 3.6).
///
/// **Layout**
/// ```
/// ┌─────────────────────────────────┐
/// │  [Camera Preview - full screen] │
/// │                                 │
/// │  [Warning Banner]    [Timer]    │  ← top HUD
/// │                                 │
/// │         [Push-Up Counter]       │  ← centre
/// │         [Form Score]            │
/// │                                 │
/// │  [Stop] [Overlay] [CamFlip]     │  ← bottom controls
/// └─────────────────────────────────┘
/// ```
///
/// **States**
/// - `.idle`: Shows a "Start" button over the camera preview.
/// - `.active`: Shows the live counter, form score, timer, and controls.
/// - `.confirmingStop`: Shows a confirmation alert.
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
            // ── Camera Layer ──────────────────────────────────────────────
            cameraLayer

            // ── Pose Overlay ──────────────────────────────────────────────
            if viewModel.showPoseOverlay {
                PoseOverlayView(
                    pose: viewModel.trackingManager.pushUpDetector.smoothedPose,
                    isVisible: viewModel.showPoseOverlay
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // ── HUD Layer (phase-dependent) ───────────────────────────────
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
            // Start the camera preview immediately so the user can see
            // themselves before tapping "Start". The tracking pipeline
            // (pose detection + push-up counting) only starts on "Start".
            // Also restart the preview when returning to the tab after
            // finishing a workout.
            if viewModel.phase == .idle || viewModel.phase == .finished {
                viewModel.cameraManager.setupAndStart(position: .front)
            }
        }
        .onDisappear {
            // Stop the camera when leaving the tab to release hardware.
            // If a workout is active, stop tracking (saves the session).
            switch viewModel.phase {
            case .idle, .finished:
                viewModel.cameraManager.stopSession()
            case .active, .confirmingStop:
                viewModel.confirmStop()
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
        switch viewModel.cameraManager.state {
        case .idle, .running, .stopped:
            CameraPreviewView(cameraManager: viewModel.cameraManager)
                .ignoresSafeArea()
        case .error(let error):
            CameraUnavailableView(error: error)
                .ignoresSafeArea()
        }
    }

    // MARK: - Idle Overlay

    private var idleOverlay: some View {
        ZStack {
            // Dark scrim so the start button is readable over any background.
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.xl) {
                Spacer()

                // App icon / branding
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

                // Start button
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
            // ── Top HUD ───────────────────────────────────────────────────
            topHUD
                .padding(.top, AppSpacing.xxl)
                .padding(.horizontal, AppSpacing.md)

            Spacer()

            // ── Centre: Counter + Form Score ──────────────────────────────
            VStack(spacing: AppSpacing.sm) {
                LiveCounterView(count: viewModel.pushUpCount)

                FormScoreIndicator(score: viewModel.formScore)
            }
            .padding(.bottom, AppSpacing.lg)

            Spacer()

            // ── Bottom Controls ───────────────────────────────────────────
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
            // Warning banner (left-aligned, fades in/out)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                WarningBannerView(warnings: viewModel.activeWarnings)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.activeWarnings)
            }

            Spacer()

            // Timer + sound toggle (right-aligned)
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
                // Checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(AppColors.success)

                Text("Workout beendet!")
                    .font(AppTypography.roundedTitle)
                    .foregroundStyle(.white)

                // Summary card
                summaryCard

                // Action buttons
                VStack(spacing: AppSpacing.sm) {
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
                }
                .padding(.horizontal, AppSpacing.xl)
            }
            .padding(AppSpacing.xl)
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryStatCell(
                value: "\(viewModel.pushUpCount)",
                label: "Push-Ups"
            )

            Divider()
                .frame(height: 40)
                .background(.white.opacity(0.2))

            summaryStatCell(
                value: formattedDuration(viewModel.sessionDuration),
                label: "Zeit"
            )

            if let score = viewModel.formScore {
                Divider()
                    .frame(height: 40)
                    .background(.white.opacity(0.2))

                summaryStatCell(
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

    private func summaryStatCell(
        value: String,
        label: String,
        valueColor: Color = .white
    ) -> some View {
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

    // MARK: - Helpers

    private var isConfirmingStop: Binding<Bool> {
        Binding(
            get: { viewModel.phase == .confirmingStop },
            set: { if !$0 { viewModel.cancelStop() } }
        )
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Workout - Idle") {
    WorkoutView()
}
#endif
