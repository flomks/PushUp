import AudioToolbox
import AVFoundation
import Combine
import Foundation
import UIKit

// MARK: - WorkoutPhase

/// The high-level state of the workout screen.
enum WorkoutPhase: Equatable, Sendable {
    /// Waiting for the user to tap "Start".
    case idle
    /// Camera is running and push-ups are being counted.
    case active
    /// The user has requested to stop; confirmation alert is shown.
    case confirmingStop
    /// The session has ended and results are available.
    case finished
}

// MARK: - WorkoutViewModel

/// Drives the Workout screen (Task 3.6).
///
/// Wraps `PushUpTrackingManager` and adds:
/// - Idle-timer management (`UIApplication.isIdleTimerDisabled`)
/// - Haptic feedback on every counted push-up
/// - Optional system sound effect on every counted push-up
/// - Stop-confirmation flow
/// - Pose-overlay toggle
/// - Camera-flip forwarding
///
/// **Design decisions**
/// - The view model does **not** expose `PushUpTrackingManager` or any of its
///   internal components directly. All access goes through scoped accessors
///   on the tracking manager to preserve encapsulation.
/// - `sessionDuration` is captured before calling `stopTracking()` because
///   the tracking manager resets its duration to 0 on stop.
///
/// **Threading model**
/// All `@Published` properties and public methods are **main-actor isolated**,
/// matching `PushUpTrackingManager`.
@MainActor
final class WorkoutViewModel: ObservableObject {

    // MARK: - Published State

    /// Current phase of the workout screen.
    @Published private(set) var phase: WorkoutPhase = .idle

    /// Total push-ups counted in the current session.
    @Published private(set) var pushUpCount: Int = 0

    /// Combined form score (0.0-1.0) of the most recently completed push-up.
    /// `nil` before the first push-up is counted.
    @Published private(set) var formScore: Double? = nil

    /// Elapsed session time in seconds. Preserved after stop for the
    /// finished overlay. Reset to `0` only on `resetForNewWorkout()`.
    @Published private(set) var sessionDuration: TimeInterval = 0

    /// Active edge-case warnings from the pose detector.
    @Published private(set) var activeWarnings: [EdgeCaseWarning] = []

    /// The most recent tracking error, or `nil` when healthy.
    @Published private(set) var lastError: TrackingError? = nil

    /// Whether the pose skeleton overlay is visible.
    @Published var showPoseOverlay: Bool = false

    /// Whether sound effects are enabled.
    @Published var soundEnabled: Bool = true

    /// The current camera position (front / back).
    @Published private(set) var cameraPosition: CameraPosition = .front

    /// The current camera state (idle / running / stopped / error).
    @Published private(set) var cameraState: CameraState = .idle

    /// The most recently detected pose for the overlay. Updated on the
    /// main queue by `VisionPoseDetector`. `nil` when no person is detected.
    @Published private(set) var currentPose: BodyPose? = nil

    // MARK: - Internal: Tracking Manager

    /// The underlying tracking manager. Kept `private` to prevent the view
    /// from reaching through to internal pipeline components.
    private let trackingManager: PushUpTrackingManager

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    /// Haptic feedback generator for push-up events.
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Init

    init(trackingManager: PushUpTrackingManager = PushUpTrackingManager()) {
        self.trackingManager = trackingManager
        bindTrackingManager()
        prepareHaptics()
    }

    // MARK: - Public API: Session Lifecycle

    /// Starts the workout session.
    func startWorkout() {
        guard phase == .idle else { return }
        phase = .active
        UIApplication.shared.isIdleTimerDisabled = true
        trackingManager.startTracking()
    }

    /// Requests confirmation before stopping. Shows the confirmation alert.
    func requestStop() {
        guard phase == .active else { return }
        phase = .confirmingStop
    }

    /// Cancels the stop request and returns to the active phase.
    func cancelStop() {
        guard phase == .confirmingStop else { return }
        phase = .active
    }

    /// Confirms the stop and ends the session.
    func confirmStop() {
        guard phase == .confirmingStop || phase == .active else { return }
        endSession()
    }

    /// Resets the view model so a new workout can be started.
    /// Also restarts the camera preview so the user can see themselves.
    func resetForNewWorkout() {
        phase = .idle
        pushUpCount = 0
        formScore = nil
        sessionDuration = 0
        activeWarnings = []
        lastError = nil
        currentPose = nil
        // Restart the camera preview for the idle state.
        trackingManager.startCameraPreview(position: .front)
    }

    // MARK: - Public API: Camera

    /// Switches between front and back camera.
    func switchCamera() {
        trackingManager.switchCamera()
    }

    /// Starts the camera preview for the idle state.
    /// Does nothing if tracking is already active.
    func startPreview() {
        trackingManager.startCameraPreview(position: .front)
    }

    /// Stops the camera preview. Only effective when not tracking.
    func stopPreview() {
        trackingManager.stopCameraPreview()
    }

    /// The preview layer for the camera feed.
    var previewLayer: AVCaptureVideoPreviewLayer {
        trackingManager.previewLayer
    }

    // MARK: - Private: Session Lifecycle

    private func endSession() {
        // Capture the final duration BEFORE stopTracking() resets it to 0.
        let finalDuration = trackingManager.sessionDuration
        trackingManager.stopTracking()
        UIApplication.shared.isIdleTimerDisabled = false
        // Restore the captured duration so the finished overlay shows it.
        sessionDuration = finalDuration
        phase = .finished
    }

    // MARK: - Private: Binding

    /// Subscribes to all relevant publishers from the tracking manager.
    ///
    /// Both `PushUpTrackingManager` and `WorkoutViewModel` are `@MainActor`,
    /// so `@Published` properties already emit on the main actor. No
    /// `.receive(on:)` is needed. Using `sink` with `[weak self]` to avoid
    /// retain cycles (unlike `assign(to:on:)` which retains `self`).
    private func bindTrackingManager() {
        let manager = trackingManager

        manager.$currentCount
            .sink { [weak self] count in
                guard let self else { return }
                let previous = self.pushUpCount
                self.pushUpCount = count
                if count > previous {
                    self.handlePushUpCounted()
                }
            }
            .store(in: &cancellables)

        manager.$currentFormScore
            .sink { [weak self] in self?.formScore = $0 }
            .store(in: &cancellables)

        manager.$sessionDuration
            .sink { [weak self] in
                guard let self else { return }
                // Only update while active; preserve final value after stop.
                if self.phase == .active || self.phase == .confirmingStop {
                    self.sessionDuration = $0
                }
            }
            .store(in: &cancellables)

        manager.$activeWarnings
            .sink { [weak self] in self?.activeWarnings = $0 }
            .store(in: &cancellables)

        manager.$lastError
            .sink { [weak self] in self?.lastError = $0 }
            .store(in: &cancellables)

        manager.cameraPositionPublisher
            .sink { [weak self] in self?.cameraPosition = $0 }
            .store(in: &cancellables)

        manager.cameraStatePublisher
            .sink { [weak self] in self?.cameraState = $0 }
            .store(in: &cancellables)

        // Subscribe to the VisionPoseDetector's main-queue-published
        // currentPose (thread-safe) for the overlay. This updates on
        // every processed frame, not just on push-up events.
        manager.currentPosePublisher
            .sink { [weak self] in self?.currentPose = $0 }
            .store(in: &cancellables)
    }

    // MARK: - Private: Push-Up Feedback

    private func handlePushUpCounted() {
        triggerHaptic()
        if soundEnabled {
            playPushUpSound()
        }
    }

    // MARK: - Private: Haptics

    private func prepareHaptics() {
        impactFeedback.prepare()
    }

    private func triggerHaptic() {
        impactFeedback.impactOccurred()
        impactFeedback.prepare()
    }

    // MARK: - Private: Audio

    private func playPushUpSound() {
        // System sound "Tock" (ID 1104) -- a short, clean click available
        // on all iOS devices without bundling a custom audio asset.
        AudioServicesPlaySystemSound(1104)
    }
}
