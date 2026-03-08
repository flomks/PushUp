import AudioToolbox
import Combine
import Foundation
import UIKit

// MARK: - WorkoutPhase

/// The high-level state of the workout screen.
enum WorkoutPhase: Equatable {
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

    /// Elapsed session time in seconds. `0` when not active.
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

    // MARK: - Internal: Tracking Manager

    /// The underlying tracking manager. Exposed as `internal` so that
    /// `WorkoutView` can access the camera manager for the preview layer.
    let trackingManager: PushUpTrackingManager

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    /// Haptic feedback generator for push-up events.
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    /// The camera manager owned by the tracking manager.
    /// Exposed so `WorkoutView` can pass it to `CameraPreviewView`.
    var cameraManager: CameraManager {
        trackingManager.cameraManager
    }

    // MARK: - Init

    init(trackingManager: PushUpTrackingManager = PushUpTrackingManager()) {
        self.trackingManager = trackingManager
        bindTrackingManager()
        prepareHaptics()
    }

    // MARK: - Public API

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
        // Restart the camera preview for the idle state.
        trackingManager.cameraManager.setupAndStart(position: .front)
    }

    /// Switches between front and back camera.
    func switchCamera() {
        trackingManager.cameraManager.switchCamera()
    }

    // MARK: - Private: Session Lifecycle

    private func endSession() {
        trackingManager.stopTracking()
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .finished
    }

    // MARK: - Private: Binding

    private func bindTrackingManager() {
        let manager = trackingManager

        manager.$currentCount
            .receive(on: DispatchQueue.main)
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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] score in self?.formScore = score }
            .store(in: &cancellables)

        manager.$sessionDuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in self?.sessionDuration = duration }
            .store(in: &cancellables)

        manager.$activeWarnings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] warnings in self?.activeWarnings = warnings }
            .store(in: &cancellables)

        manager.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in self?.lastError = error }
            .store(in: &cancellables)

        manager.cameraManager.$currentPosition
            .receive(on: DispatchQueue.main)
            .sink { [weak self] position in self?.cameraPosition = position }
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
        // Re-prepare so the next impact is ready immediately.
        impactFeedback.prepare()
    }

    // MARK: - Private: Audio

    private func playPushUpSound() {
        // Use system sound "Tock" (ID 1104) -- a short, clean click
        // that is available on all iOS devices without bundling an asset.
        AudioServicesPlaySystemSound(1104)
    }
}
