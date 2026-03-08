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
    @State private var cameraPosition: CameraPosition = .back

    var body: some View {
        ZStack {
            // MARK: Camera feed (full screen)
            CameraContainerView(
                onSampleBuffer: { [weak viewModel] buf in
                    // NOTE: cameraPosition is read on the video output queue.
                    // @State is main-actor-isolated, but reading a simple enum
                    // value here is safe: worst case we use a stale value for
                    // one frame, which causes no visible artefact.
                    viewModel?.process(buf)
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
                // Top bar: phase + overlay toggle
                topBar

                Spacer()

                // Bottom card: counter + angle + warnings
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
        VStack(spacing: 8) {
            HStack {
                // Phase pill
                Label(viewModel.phaseLabel, systemImage: viewModel.phaseIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())

                Spacer()

                // Skeleton overlay toggle
                Button {
                    showPoseOverlay.toggle()
                } label: {
                    Image(systemName: showPoseOverlay ? "figure.arms.open" : "figure.stand")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(showPoseOverlay ? Color.green : Color.white.opacity(0.6))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(showPoseOverlay ? "Skeleton overlay on" : "Skeleton overlay off")
            }

            // Status indicator
            HStack(spacing: 6) {
                Image(systemName: viewModel.detectionStatus.icon)
                    .font(.caption2)
                Text(viewModel.detectionStatus.label)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(viewModel.detectionStatus.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .animation(.easeInOut(duration: 0.3), value: viewModel.detectionStatus)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Bottom card

    private var bottomCard: some View {
        VStack(spacing: 8) {

            // Warnings (poor angle, poor lighting, etc.)
            if !viewModel.warnings.isEmpty {
                VStack(spacing: 4) {
                    ForEach(viewModel.warnings, id: \.self) { warning in
                        Label(warning.userMessage, systemImage: warningIcon(for: warning))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.yellow)
                    }
                }
                .padding(.bottom, 4)
            }

            // Push-up counter
            Text("\(viewModel.pushUpCount)")
                .font(.system(size: 96, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: viewModel.pushUpCount)

            Text("Push-Ups")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))

            // Half-rep indicator
            if viewModel.halfRepCount > 0 {
                Text("\(viewModel.halfRepCount) halbe")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            // Variant badge + body-line
            HStack(spacing: 12) {
                // Push-up variant
                if viewModel.positionState.isHorizontal {
                    Text(viewModel.positionState.variant.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(variantColor, in: Capsule())
                }

                // Elbow angle
                if let angle = viewModel.currentAngle {
                    HStack(spacing: 4) {
                        Image(systemName: "angle")
                        Text(String(format: "%.0f°", angle))
                            .monospacedDigit()
                    }
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                }

                // Body-line deviation
                if let dev = viewModel.bodyLineDeviation {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.stand")
                        Text(String(format: "%.0f°", dev))
                            .monospacedDigit()
                    }
                    .font(.callout)
                    .foregroundStyle(bodyLineColor(dev))
                }
            }
            .padding(.top, 4)

            if viewModel.currentAngle == nil {
                Label("Kein Arm erkannt", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }

            // Reset button
            Button {
                viewModel.reset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }

    // MARK: - Helpers

    private var variantColor: Color {
        switch viewModel.positionState.variant {
        case .unknown: return .gray
        case .normal:  return .green
        case .decline: return .orange
        case .incline: return .blue
        }
    }

    private func bodyLineColor(_ deviation: Double) -> Color {
        if deviation < 15 { return .green }
        if deviation < 35 { return .yellow }
        return .red
    }

    private func warningIcon(for warning: EdgeCaseWarning) -> String {
        switch warning {
        case .noPersonDetected:      return "person.slash"
        case .poorAngle:             return "arrow.left.and.right.square"
        case .poorLighting:          return "sun.min"
        case .multiplePersonsDetected: return "person.2"
        }
    }
}

// MARK: - DetectionStatus

/// Status of the detection pipeline, shown as a small indicator in the UI.
enum DetectionStatus: Equatable {
    /// App just started, camera not yet delivering frames.
    case initializing
    /// Camera is running but no person detected yet.
    case noPerson
    /// Person detected but arm joints not visible (wrong angle?).
    case personNoArms
    /// Person detected with arm joints -- ready to track.
    case tracking
    /// Actively counting (in DOWN or COOLDOWN phase).
    case active

    var label: String {
        switch self {
        case .initializing:  return "Starte Kamera..."
        case .noPerson:      return "Keine Person erkannt"
        case .personNoArms:  return "Arme nicht sichtbar"
        case .tracking:      return "Bereit"
        case .active:        return "Tracking aktiv"
        }
    }

    var icon: String {
        switch self {
        case .initializing:  return "camera"
        case .noPerson:      return "person.slash"
        case .personNoArms:  return "eye.slash"
        case .tracking:      return "checkmark.circle"
        case .active:        return "figure.run"
        }
    }

    var color: Color {
        switch self {
        case .initializing:  return .gray
        case .noPerson:      return .red
        case .personNoArms:  return .orange
        case .tracking:      return .green
        case .active:        return .green
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
    nonisolated(unsafe) var cameraPosition: CameraPosition = .back

    private let poseDetector = VisionPoseDetector()

    /// Accessed from the video output queue inside `didDetectPose` and from
    /// the main actor inside `reset()`. These two call sites are serialised by
    /// the app's usage pattern (reset is only called when no workout is
    /// running), so `nonisolated(unsafe)` is correct here.
    nonisolated(unsafe) private let pushUpDetector = PushUpDetector()

    init() {
        poseDetector.delegate = PoseDetectorBridge(viewModel: self)
        pushUpDetector.delegate = PushUpDetectorBridge(viewModel: self)
    }

    /// Called from the video output queue (background thread).
    /// `nonisolated` so the `@Sendable` closure in `CameraContainerView`
    /// can call it directly without hopping to the main actor.
    nonisolated func process(_ sampleBuffer: CMSampleBuffer) {
        // Read cameraPosition without a main-actor hop. The value is a simple
        // enum; a one-frame stale read causes no visible artefact.
        let position = cameraPosition
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

        // Compute detection status
        let status: DetectionStatus
        if pose == nil {
            status = .noPerson
        } else if angle == nil {
            status = .personNoArms
        } else if phase == .down || phase == .cooldown {
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
        case .idle:     return "Bereit"
        case .down:     return "Runter"
        case .cooldown: return "Hoch!"
        }
    }

    var phaseIcon: String {
        switch currentPhase {
        case .idle:     return "figure.stand"
        case .down:     return "arrow.down.circle.fill"
        case .cooldown: return "checkmark.circle.fill"
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
