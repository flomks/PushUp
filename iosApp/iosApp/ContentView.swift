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

    /// Stable `@Sendable` closure stored in `@State` so it is created once
    /// and never re-allocated on subsequent `body` evaluations.
    @State private var sampleBufferProcessor: (@Sendable (CMSampleBuffer) -> Void)?

    var body: some View {
        ZStack {
            // MARK: Camera feed (full screen)
            CameraContainerView(onSampleBuffer: sampleBufferProcessor)
                .ignoresSafeArea()

            // MARK: Skeleton overlay
            PoseOverlayView(
                pose: viewModel.currentPose,
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
            if sampleBufferProcessor == nil {
                let vm = viewModel
                sampleBufferProcessor = { buf in vm.process(buf) }
            }
            viewModel.reset()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
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

            // Elbow angle gauge — only shown when a pose is detected
            if let angle = viewModel.currentAngle {
                HStack(spacing: 6) {
                    Image(systemName: "angle")
                        .foregroundStyle(.white.opacity(0.7))
                    Text(String(format: "%.0f°", angle))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.top, 4)
            } else {
                // No pose detected hint
                Label("Kein Arm erkannt", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 4)
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

    private func warningIcon(for warning: EdgeCaseWarning) -> String {
        switch warning {
        case .noPersonDetected:      return "person.slash"
        case .poorAngle:             return "arrow.left.and.right.square"
        case .poorLighting:          return "sun.min"
        case .multiplePersonsDetected: return "person.2"
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
    @Published private(set) var currentAngle: Double? = nil
    @Published private(set) var currentPhase: PushUpPhase = .idle
    @Published private(set) var currentPose: BodyPose? = nil
    @Published private(set) var warnings: [EdgeCaseWarning] = []

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
        poseDetector.process(sampleBuffer)
    }

    func reset() {
        pushUpDetector.reset()
        pushUpCount = 0
        currentAngle = nil
        currentPhase = .idle
        currentPose = nil
        warnings = []
    }

    // Called from the video output queue via the bridge.
    nonisolated func didDetectPose(_ pose: BodyPose?, warnings: [EdgeCaseWarning]) {
        pushUpDetector.process(pose)
        let angle = pushUpDetector.currentElbowAngle
        let phase = pushUpDetector.currentPhase
        let count = pushUpDetector.pushUpCount
        Task { @MainActor in
            self.currentPose  = pose
            self.currentAngle = angle
            self.currentPhase = phase
            self.pushUpCount  = count
            self.warnings     = warnings
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
