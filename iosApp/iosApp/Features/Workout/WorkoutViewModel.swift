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

/// Drives the Workout screen (Tasks 3.6 and 3.7).
///
/// Wraps `PushUpTrackingManager` and adds:
/// - Idle-timer management (`UIApplication.isIdleTimerDisabled`)
/// - Haptic feedback on every counted push-up
/// - Optional system sound effect on every counted push-up
/// - Stop-confirmation flow
/// - Pose-overlay toggle
/// - Camera-flip forwarding
/// - Summary data for the completion screen (earned minutes, personal record)
///
/// **Design decisions**
/// - The view model does **not** expose `PushUpTrackingManager` or any of its
///   internal components directly. All access goes through scoped accessors
///   on the tracking manager to preserve encapsulation.
/// - `sessionDuration` is captured before calling `stopTracking()` because
///   the tracking manager resets its duration to 0 on stop.
/// - Earned minutes are computed from push-up count using a simple formula:
///   1 minute per 10 push-ups (minimum 1 minute for any completed session).
/// - Personal record detection compares the current session's push-up count
///   against the stored best. In the absence of a persistence layer the best
///   is tracked in-memory for the app session.
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
    @Published private(set) var cameraPosition: DeviceLens = DeviceLens.front

    /// The current camera state (idle / running / stopped / error).
    @Published private(set) var cameraState: CameraState = .idle

    /// The most recently detected pose for the overlay. Updated on the
    /// main queue by `VisionPoseDetector`. `nil` when no person is detected.
    @Published private(set) var currentPose: BodyPose? = nil

    // MARK: - Summary State (Task 3.7)

    /// Whether the completed session is a new personal record.
    @Published private(set) var isNewRecord: Bool = false

    /// Percentage difference vs. the user's personal average push-up count.
    /// Positive = above average, negative = below average.
    /// `nil` when fewer than 2 sessions have been completed.
    @Published private(set) var comparisonPercent: Int? = nil

    // MARK: - Internal: Tracking Manager

    /// The underlying tracking manager. Kept `private` to prevent the view
    /// from reaching through to internal pipeline components.
    private let trackingManager: PushUpTrackingManager

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    /// Running total of all push-ups across sessions (for average calculation).
    private var totalHistoricalPushUps: Int = 0

    /// Number of completed sessions (for average calculation).
    private var completedSessionCount: Int = 0

    /// Personal best push-up count across all sessions.
    private var personalBest: Int = 0

    /// Haptic feedback generator for push-up events.
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Init

    init(trackingManager: PushUpTrackingManager? = nil) {
        self.trackingManager = trackingManager ?? PushUpTrackingManager()
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
        isNewRecord = false
        comparisonPercent = nil
        // Restart the camera preview for the idle state.
        trackingManager.startCameraPreview(position: DeviceLens.front)
    }

    // MARK: - Public API: Summary (Task 3.7)

    /// Time credit earned for the completed session in whole minutes.
    ///
    /// Formula: 1 minute per 10 push-ups, minimum 1 minute for any session
    /// that has at least 1 push-up. Returns 0 for empty sessions.
    var earnedMinutes: Int {
        guard pushUpCount > 0 else { return 0 }
        return max(1, pushUpCount / 10)
    }

    // MARK: - Public API: Camera

    /// Switches between front and back camera.
    func switchCamera() {
        trackingManager.switchCamera()
    }

    /// Starts the camera preview for the idle state.
    /// Does nothing if tracking is already active.
    func startPreview() {
        trackingManager.startCameraPreview(position: DeviceLens.front)
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

        // Compute summary statistics for the completion screen (Task 3.7).
        computeSummaryStats()

        phase = .finished

        // Fire the post-workout local notification (Task 3.12).
        // Only send when at least one push-up was counted.
        if pushUpCount > 0 {
            let minutes = earnedMinutes
            Task {
                await NotificationManager.shared.scheduleWorkoutCompleteNotification(
                    earnedMinutes: minutes
                )
            }
        }
    }

    /// Computes personal-record and comparison statistics for the summary screen.
    ///
    /// Updates `isNewRecord` and `comparisonPercent` based on the session's
    /// push-up count vs. historical data tracked in-memory.
    private func computeSummaryStats() {
        let count = pushUpCount

        // Personal record check
        if count > personalBest {
            isNewRecord = personalBest > 0 // Only a "new record" if there was a previous best
            personalBest = count
        } else {
            isNewRecord = false
        }

        // Comparison to personal average
        if completedSessionCount > 0 {
            let average = Double(totalHistoricalPushUps) / Double(completedSessionCount)
            if average > 0 {
                let diff = Double(count) - average
                comparisonPercent = Int((diff / average * 100).rounded())
            } else {
                comparisonPercent = nil
            }
        } else {
            comparisonPercent = nil
        }

        // Update historical data for future sessions
        totalHistoricalPushUps += count
        completedSessionCount += 1
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
            .sink { [weak self] (position: DeviceLens) in self?.cameraPosition = position }
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
