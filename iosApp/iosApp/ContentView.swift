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

    var body: some View {
        ZStack {
            // MARK: Camera feed (full screen)
            CameraContainerView { sampleBuffer in
                viewModel.process(sampleBuffer)
            }
            .ignoresSafeArea()

            // MARK: Overlay
            VStack {
                // Top bar: phase indicator
                phaseBar

                Spacer()

                // Bottom card: counter + angle
                bottomCard
            }
        }
        .onAppear { viewModel.reset() }
    }

    // MARK: - Subviews

    private var phaseBar: some View {
        HStack {
            Label(viewModel.phaseLabel, systemImage: viewModel.phaseIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var bottomCard: some View {
        VStack(spacing: 8) {
            // Push-up counter
            Text("\(viewModel.pushUpCount)")
                .font(.system(size: 96, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: viewModel.pushUpCount)

            Text("Push-Ups")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))

            // Elbow angle gauge
            if let angle = viewModel.currentAngle {
                HStack(spacing: 6) {
                    Image(systemName: "angle")
                        .foregroundStyle(.white.opacity(0.7))
                    Text(String(format: "%.0f°", angle))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
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

    private let poseDetector = VisionPoseDetector()
    private let pushUpDetector = PushUpDetector()

    init() {
        poseDetector.delegate = PoseDetectorBridge(viewModel: self)
        pushUpDetector.delegate = PushUpDetectorBridge(viewModel: self)
    }

    func process(_ sampleBuffer: CMSampleBuffer) {
        poseDetector.process(sampleBuffer)
    }

    func reset() {
        pushUpDetector.reset()
        pushUpCount = 0
        currentAngle = nil
        currentPhase = .idle
    }

    // Called from the video output queue via the bridge.
    nonisolated func didDetectPose(_ pose: BodyPose?) {
        pushUpDetector.process(pose)
        let angle = pushUpDetector.currentElbowAngle
        let phase = pushUpDetector.currentPhase
        let count = pushUpDetector.pushUpCount
        Task { @MainActor in
            self.currentAngle = angle
            self.currentPhase = phase
            self.pushUpCount  = count
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
    func poseDetector(_ detector: VisionPoseDetector, didDetect pose: BodyPose?) {
        viewModel?.didDetectPose(pose)
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
