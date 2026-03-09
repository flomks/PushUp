import AVFoundation
import SwiftUI

// MARK: - ContentView

/// Root view of the app. Wires together the camera, pose detector, and
/// push-up detector into a single live demo screen.
///
/// This is a functional demo screen for Task 2.3. The full workout UI
/// (Task 3.6) will replace this in a later phase.
struct ContentView: View {

    @StateObject private var viewModel = PushUpDemoViewModel()

    /// Toggles the skeleton/joint debug overlay on the camera feed.
    @State private var showPoseOverlay: Bool = true

    /// Tracks the active camera lens so Vision gets the correct pixel-buffer
    /// orientation. Updated by CameraContainerView via its cameraManager.
    @State private var cameraPosition: DeviceLens = .back

    var body: some View {
        ZStack {
            // MARK: Camera feed (full screen)
            CameraContainerView(
                onSampleBuffer: { buf in
                    viewModel.process(buf)
                },
                onPositionChange: { newPosition in
                    cameraPosition = newPosition
                }
            )
            .ignoresSafeArea()

            // MARK: Skeleton overlay (uses smoothed pose to reduce jitter)
            PoseOverlayView(
                pose: viewModel.smoothedPose ?? viewModel.currentPose,
                isVisible: showPoseOverlay
            )
            .ignoresSafeArea()

            // MARK: HUD
            VStack {
                topBar
                Spacer()
                bottomCard
            }
        }
        .onAppear {
            viewModel.cameraPosition = cameraPosition
            viewModel.reset()
        }
        .onChange(of: cameraPosition) { newPosition in
            viewModel.cameraPosition = newPosition
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: AppSpacing.xs) {
            HStack {
                // Phase pill
                Label(viewModel.phaseLabel, systemImage: viewModel.phaseIcon)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.sm + 2)
                    .padding(.vertical, AppSpacing.xs)
                    .background(.ultraThinMaterial, in: Capsule())

                Spacer()

                // Skeleton overlay toggle
                Button {
                    showPoseOverlay.toggle()
                } label: {
                    Image(systemName: showPoseOverlay
                          ? AppIcon.figureArmsOpen.rawValue
                          : AppIcon.figureStand.rawValue)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(showPoseOverlay ? AppColors.success : .white.opacity(0.6))
                        .padding(AppSpacing.xs + 2)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(showPoseOverlay ? "Skeleton overlay on" : "Skeleton overlay off")
            }

            // Status indicator
            HStack(spacing: AppSpacing.xxs + 2) {
                Image(systemName: viewModel.detectionStatus.icon)
                    .font(AppTypography.caption2)
                Text(viewModel.detectionStatus.label)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(viewModel.detectionStatus.color)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .animation(.easeInOut(duration: 0.3), value: viewModel.detectionStatus)
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.top, AppSpacing.screenHorizontal)
    }

    // MARK: - Bottom card

    private var bottomCard: some View {
        VStack(spacing: AppSpacing.xs) {

            // Warnings (poor angle, poor lighting, etc.)
            if !viewModel.warnings.isEmpty {
                VStack(spacing: AppSpacing.xxs) {
                    ForEach(viewModel.warnings, id: \.self) { warning in
                        Label(warning.userMessage, systemImage: warningIcon(for: warning))
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(AppColors.warning)
                    }
                }
                .padding(.bottom, AppSpacing.xxs)
            }

            // Push-up counter
            Text("\(viewModel.pushUpCount)")
                .font(AppTypography.displayCounter)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: viewModel.pushUpCount)

            Text("Push-Ups")
                .font(AppTypography.title3)
                .foregroundStyle(.white.opacity(0.8))

            // Half-rep indicator
            if viewModel.halfRepCount > 0 {
                Text("\(viewModel.halfRepCount) half reps")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.secondary)
            }

            // Variant badge + body-line
            HStack(spacing: AppSpacing.sm) {
                // Push-up variant
                if viewModel.positionState.isHorizontal {
                    Text(viewModel.positionState.variant.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, AppSpacing.xs + 2)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(variantColor, in: Capsule())
                }

                // Elbow angle
                if let angle = viewModel.currentAngle {
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: AppIcon.angle.rawValue)
                        Text(String(format: "%.0f\u{00B0}", angle))
                            .monospacedDigit()
                    }
                    .font(AppTypography.callout)
                    .foregroundStyle(.white.opacity(0.7))
                }

                // Body-line deviation
                if let dev = viewModel.bodyLineDeviation {
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: AppIcon.figureStand.rawValue)
                        Text(String(format: "%.0f\u{00B0}", dev))
                            .monospacedDigit()
                    }
                    .font(AppTypography.callout)
                    .foregroundStyle(bodyLineColor(dev))
                }
            }
            .padding(.top, AppSpacing.xxs)

            if viewModel.currentAngle == nil {
                Label("No arm detected", systemImage: AppIcon.eyeSlash.rawValue)
                    .font(AppTypography.caption1)
                    .foregroundStyle(.white.opacity(0.45))
            }

            // Reset button
            Button {
                viewModel.reset()
            } label: {
                Label("Reset", systemImage: AppIcon.arrowCounterclockwise.rawValue)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.lg - 4)
                    .padding(.vertical, AppSpacing.xs + 2)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.top, AppSpacing.xs)
        }
        .padding(.vertical, AppSpacing.lg + 4)
        .padding(.horizontal, AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge + 4))
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.bottom, AppSpacing.xxl - 8)
    }

    // MARK: - Helpers

    private var variantColor: Color {
        switch viewModel.positionState.variant {
        case .unknown: return AppColors.textSecondary
        case .normal:  return AppColors.success
        case .decline: return AppColors.warning
        case .incline: return AppColors.info
        }
    }

    private func bodyLineColor(_ deviation: Double) -> Color {
        if deviation < 15 { return AppColors.success }
        if deviation < 35 { return AppColors.warning }
        return AppColors.error
    }

    private func warningIcon(for warning: EdgeCaseWarning) -> String {
        switch warning {
        case .noPersonDetected:        return AppIcon.personSlash.rawValue
        case .poorAngle:               return AppIcon.arrowLeftAndRightSquare.rawValue
        case .poorLighting:            return AppIcon.sunMin.rawValue
        case .multiplePersonsDetected: return AppIcon.person2.rawValue
        }
    }
}

// MARK: - DetectionStatus

/// Status of the detection pipeline, shown as a small indicator in the UI.
enum DetectionStatus: Equatable {
    case initializing
    case noPerson
    case personNoArms
    case tracking
    case active

    var label: String {
        switch self {
        case .initializing:  return "Starting camera..."
        case .noPerson:      return "No person detected"
        case .personNoArms:  return "Arms not visible"
        case .tracking:      return "Ready"
        case .active:        return "Tracking active"
        }
    }

    var icon: String {
        switch self {
        case .initializing:  return AppIcon.camera.rawValue
        case .noPerson:      return AppIcon.personSlash.rawValue
        case .personNoArms:  return AppIcon.eyeSlash.rawValue
        case .tracking:      return AppIcon.checkmarkCircle.rawValue
        case .active:        return AppIcon.figureRun.rawValue
        }
    }

    var color: Color {
        switch self {
        case .initializing:  return AppColors.textSecondary
        case .noPerson:      return AppColors.error
        case .personNoArms:  return AppColors.warning
        case .tracking:      return AppColors.success
        case .active:        return AppColors.success
        }
    }
}

// MARK: - PushUpDemoViewModel

/// Owns the pose detector and push-up detector. Publishes state for the UI.
///
/// All Vision / push-up processing happens on the video output queue.
/// Published properties are updated on the main queue.
@MainActor
final class PushUpDemoViewModel: ObservableObject {

    @Published private(set) var pushUpCount: Int = 0
    @Published private(set) var halfRepCount: Int = 0
    @Published private(set) var currentAngle: Double? = nil
    @Published private(set) var currentPhase: PushUpPhase = .idle
    @Published private(set) var currentPose: BodyPose? = nil
    @Published private(set) var warnings: [EdgeCaseWarning] = []
    @Published private(set) var bodyLineDeviation: Double? = nil
    @Published private(set) var positionState = PositionState()
    @Published private(set) var smoothedPose: BodyPose? = nil

    /// Detection pipeline status for the status indicator.
    @Published private(set) var detectionStatus: DetectionStatus = .initializing
    /// Number of frames processed (for "running" confirmation).
    nonisolated(unsafe) private var framesProcessed: Int = 0

    /// The active camera lens. Set from ContentView (main actor) whenever the
    /// position changes. Read from the video output queue inside process(_:).
    /// nonisolated(unsafe) is correct: writes happen on the main actor before
    /// any frame arrives, and a one-frame stale read causes no visible artefact.
    nonisolated(unsafe) var cameraPosition: DeviceLens = .back

    private let poseDetector = VisionPoseDetector()

    /// Accessed from the video output queue inside `didDetectPose` and from
    /// the main actor inside `reset()`. These two call sites are serialised by
    /// the app's usage pattern (reset is only called when no workout is
    /// running), so `nonisolated(unsafe)` is correct here.
    nonisolated(unsafe) private let pushUpDetector = PushUpDetector()

    /// Strong references to the delegate bridges. Without these, the bridges
    /// are immediately deallocated after init() because both
    /// poseDetector.delegate and pushUpDetector.delegate are weak references.
    /// When the bridges are deallocated, the delegates become nil and
    /// didDetectPose / didCountPushUp are never called.
    private var poseDetectorBridge: PoseDetectorBridge?
    private var pushUpDetectorBridge: PushUpDetectorBridge?

    init() {
        let poseBridge = PoseDetectorBridge(viewModel: self)
        let pushUpBridge = PushUpDetectorBridge(viewModel: self)
        self.poseDetectorBridge = poseBridge
        self.pushUpDetectorBridge = pushUpBridge
        poseDetector.delegate = poseBridge
        pushUpDetector.delegate = pushUpBridge
    }

    /// Called from the video output queue (background thread).
    /// `nonisolated` so the `@Sendable` closure in `CameraContainerView`
    /// can call it directly without hopping to the main actor.
    nonisolated func process(_ sampleBuffer: CMSampleBuffer) {
        let position = cameraPosition
        if framesProcessed == 0 {
            Task { @MainActor in
                if self.detectionStatus == .initializing {
                    self.detectionStatus = .noPerson
                }
            }
        }
        framesProcessed += 1
        poseDetector.process(sampleBuffer, cameraPosition: position)
    }

    func reset() {
        pushUpDetector.reset()
        pushUpCount = 0
        halfRepCount = 0
        currentAngle = nil
        currentPhase = .idle
        currentPose = nil
        warnings = []
        bodyLineDeviation = nil
        positionState = PositionState()
        smoothedPose = nil
    }

    // Called from the video output queue via the bridge.
    nonisolated func didDetectPose(_ pose: BodyPose?, warnings: [EdgeCaseWarning]) {
        framesProcessed += 1
        pushUpDetector.process(pose)
        let angle     = pushUpDetector.currentElbowAngle
        let phase     = pushUpDetector.currentPhase
        let count     = pushUpDetector.pushUpCount
        let halfCount = pushUpDetector.halfRepCount
        let bodyLine  = pushUpDetector.bodyLineDeviation
        let posState  = pushUpDetector.positionState
        let smoothed  = pushUpDetector.smoothedPose

        let hasPose  = pose != nil
        let hasAngle = angle != nil
        let isActive = phase == .down || phase == .cooldown

        #if DEBUG
        if framesProcessed % 30 == 0 {
            print("[ViewModel] frame=\(framesProcessed) pose=\(hasPose) angle=\(String(describing: angle)) warnings=\(warnings.map(\.description))")
        }
        #endif

        let status: DetectionStatus
        if !hasPose {
            status = .noPerson
        } else if !hasAngle {
            status = .personNoArms
        } else if isActive {
            status = .active
        } else {
            status = .tracking
        }

        Task { @MainActor in
            self.currentPose       = pose
            self.currentAngle      = angle
            self.currentPhase      = phase
            self.pushUpCount       = count
            self.halfRepCount      = halfCount
            self.warnings          = warnings
            self.bodyLineDeviation = bodyLine
            self.positionState     = posState
            self.smoothedPose      = smoothed
            self.detectionStatus   = status
        }
    }

    nonisolated func didCountPushUp(_ event: PushUpEvent) {
        Task { @MainActor in
            self.pushUpCount = event.count
        }
    }

    // MARK: UI helpers

    var phaseLabel: String {
        switch currentPhase {
        case .idle:     return "Ready"
        case .down:     return "Down"
        case .cooldown: return "Up!"
        }
    }

    var phaseIcon: String {
        switch currentPhase {
        case .idle:     return AppIcon.figureStand.rawValue
        case .down:     return AppIcon.arrowDownCircleFill.rawValue
        case .cooldown: return AppIcon.checkmarkCircleFill.rawValue
        }
    }
}

// MARK: - Bridges (non-isolated delegates)

/// Bridges `PoseDetectorDelegate` callbacks (video queue) to the view model.
private final class PoseDetectorBridge: PoseDetectorDelegate, @unchecked Sendable {
    private weak var viewModel: PushUpDemoViewModel?
    init(viewModel: PushUpDemoViewModel) { self.viewModel = viewModel }
    func poseDetector(
        _ detector: VisionPoseDetector,
        didDetect pose: BodyPose?,
        warnings: [EdgeCaseWarning]
    ) {
        viewModel?.didDetectPose(pose, warnings: warnings)
    }
}

/// Bridges `PushUpDetectorDelegate` callbacks (video queue) to the view model.
private final class PushUpDetectorBridge: PushUpDetectorDelegate, @unchecked Sendable {
    private weak var viewModel: PushUpDemoViewModel?
    init(viewModel: PushUpDemoViewModel) { self.viewModel = viewModel }
    func pushUpDetector(_ detector: PushUpDetector, didCount event: PushUpEvent) {
        viewModel?.didCountPushUp(event)
    }
}
