import AVFoundation
import Foundation
import shared

// MARK: - TrackingError

/// Errors that can occur during a push-up tracking session.
///
/// Observe `PushUpTrackingManager.lastError` to react to these in the UI.
enum TrackingError: LocalizedError, Equatable {
    case alreadyTracking
    case notTracking
    case cameraError(CameraError)
    case workoutStartFailed(String)
    case workoutFinishFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyTracking:
            return "A tracking session is already in progress."
        case .notTracking:
            return "No tracking session is currently active."
        case .cameraError(let error):
            return error.errorDescription
        case .workoutStartFailed(let reason):
            return "Failed to start workout: \(reason)"
        case .workoutFinishFailed(let reason):
            return "Failed to finish workout: \(reason)"
        }
    }
}

// MARK: - PushUpTrackingManager

/// Connects the camera pipeline (Task 2.4) with the KMP business logic (Phase 1A).
///
/// **Responsibilities**
/// - Owns and wires `CameraManager`, `VisionPoseDetector`, and `PushUpDetector`.
/// - On `startTracking()`: requests camera permission, starts the capture session,
///   and calls `StartWorkoutUseCase` (KMP) to create a new workout session.
/// - On each detected push-up: calls `RecordPushUpUseCase` (KMP) with the
///   form scores from `PushUpDetector`.
/// - On `stopTracking()`: stops the camera, releases resources, and calls
///   `FinishWorkoutUseCase` (KMP) to finalise the session.
/// - Publishes `currentCount`, `currentFormScore`, `isTracking`, `sessionDuration`,
///   and `lastError` for SwiftUI consumers.
///
/// **Threading model**
/// - All `@Published` properties and public methods are **main-actor isolated**.
/// - Camera frames and pose/push-up detection run on the video output queue.
/// - KMP use-case calls are dispatched to a background `Task` and their
///   results are marshalled back to the main actor.
///
/// **Memory management**
/// - `stopTracking()` stops the `AVCaptureSession` and clears the delegate
///   chain, releasing the camera hardware and Vision pipeline.
/// - The session timer is invalidated synchronously in `stopTracking()`.
///
/// **Usage**
/// ```swift
/// // Requires KoinIOSKt.doInitKoin() to have been called at app startup.
/// let manager = PushUpTrackingManager()
/// manager.startTracking()
///
/// // Observe published properties:
/// manager.$currentCount
///     .sink { count in print("Push-ups: \(count)") }
///     .store(in: &cancellables)
///
/// manager.stopTracking()
/// ```
@MainActor
final class PushUpTrackingManager: ObservableObject {

    // MARK: - Published State

    /// Total push-ups counted in the current session.
    @Published private(set) var currentCount: Int = 0

    /// The combined form score (0.0–1.0) of the most recently completed push-up,
    /// or `nil` when no push-up has been counted yet in this session.
    @Published private(set) var currentFormScore: Double? = nil

    /// `true` while a tracking session is active (camera running + KMP session open).
    @Published private(set) var isTracking: Bool = false

    /// Elapsed time of the current session in seconds. `0` when not tracking.
    @Published private(set) var sessionDuration: TimeInterval = 0

    /// The most recent error, or `nil` when the last operation succeeded.
    /// Reset to `nil` at the start of each `startTracking()` call.
    @Published private(set) var lastError: TrackingError? = nil

    // MARK: - Private: Camera & Detection Pipeline

    private let cameraManager: CameraManager
    private let poseDetector: VisionPoseDetector

    /// `PushUpDetector` is a `final class` with its own internal locking for
    /// the delegate property. `process(_:)` is designed to be called from the
    /// video output queue. Storing it as a plain `let` is safe because the
    /// reference itself never changes after `init`.
    private let pushUpDetector: PushUpDetector

    // MARK: - Private: KMP Use Cases

    private let getOrCreateLocalUser: GetOrCreateLocalUserUseCase
    private let startWorkout: StartWorkoutUseCase
    private let recordPushUp: RecordPushUpUseCase
    private let finishWorkout: FinishWorkoutUseCase

    // MARK: - Private: Session State

    /// The KMP session ID returned by `StartWorkoutUseCase`. Non-nil while a
    /// KMP session is open. Set to non-nil only after `startKMPWorkout` succeeds,
    /// and cleared synchronously at the start of `stopTracking()`.
    private var activeSessionId: String? = nil

    /// Timestamp when the current session started. Used to compute `sessionDuration`.
    private var sessionStartDate: Date? = nil

    /// Timer that fires every second to update `sessionDuration`.
    /// Always invalidated synchronously in `stopTracking()` before any async work.
    private var sessionTimer: Timer? = nil

    /// Timestamp of the most recently counted push-up (seconds since device boot,
    /// from `PushUpEvent.timestamp`). Used to compute `durationMs` for
    /// `RecordPushUpUseCase`. Main-actor isolated.
    private var lastPushUpTimestamp: Double? = nil

    // MARK: - Init

    /// Creates a manager with explicit use-case dependencies.
    ///
    /// Use this initialiser in tests or when you want to supply mock use cases.
    ///
    /// - Parameters:
    ///   - cameraManager: The camera manager to use. Defaults to a new instance.
    ///   - poseDetector: The Vision pose detector. Defaults to a new instance.
    ///   - pushUpDetector: The push-up detector. Defaults to a new instance.
    ///   - getOrCreateLocalUser: Use case for resolving the local user ID.
    ///   - startWorkout: Use case for starting a KMP workout session.
    ///   - recordPushUp: Use case for recording a single push-up rep.
    ///   - finishWorkout: Use case for finishing the KMP workout session.
    init(
        cameraManager: CameraManager = CameraManager(),
        poseDetector: VisionPoseDetector = VisionPoseDetector(),
        pushUpDetector: PushUpDetector = PushUpDetector(),
        getOrCreateLocalUser: GetOrCreateLocalUserUseCase,
        startWorkout: StartWorkoutUseCase,
        recordPushUp: RecordPushUpUseCase,
        finishWorkout: FinishWorkoutUseCase
    ) {
        self.cameraManager = cameraManager
        self.poseDetector = poseDetector
        self.pushUpDetector = pushUpDetector
        self.getOrCreateLocalUser = getOrCreateLocalUser
        self.startWorkout = startWorkout
        self.recordPushUp = recordPushUp
        self.finishWorkout = finishWorkout

        wireDetectionPipeline()
    }

    /// Convenience initialiser that resolves use cases from the Koin DI graph.
    ///
    /// Requires `KoinIOSKt.doInitKoin()` to have been called at app startup
    /// before this initialiser is invoked.
    convenience init() {
        let helper = DIHelper.shared
        self.init(
            getOrCreateLocalUser: helper.getOrCreateLocalUserUseCase(),
            startWorkout: helper.startWorkoutUseCase(),
            recordPushUp: helper.recordPushUpUseCase(),
            finishWorkout: helper.finishWorkoutUseCase()
        )
    }

    /// `deinit` is `nonisolated` because ARC calls it from an arbitrary thread.
    /// All mutable state that needs cleanup is handled synchronously in
    /// `stopTracking()`. The timer invalidation here is a last-resort safety net
    /// for cases where the owner forgets to call `stopTracking()`.
    nonisolated deinit {
        // `Timer.invalidate()` is thread-safe when the timer has already been
        // invalidated (no-op). If `stopTracking()` was called correctly this is
        // always a no-op. We access `sessionTimer` without the main actor here
        // only as a safety net; the real cleanup path is `stopTracking()`.
        // Using MainActor.assumeIsolated would crash if not on main thread, so
        // we use a fire-and-forget dispatch instead.
        DispatchQueue.main.async { [weak self] in
            self?.sessionTimer?.invalidate()
            self?.sessionTimer = nil
        }
    }

    // MARK: - Public API

    /// Starts a push-up tracking session.
    ///
    /// 1. Validates that no session is already active.
    /// 2. Resets the detection pipeline and clears any previous error.
    /// 3. Starts the camera (requests permission if needed).
    /// 4. Calls `StartWorkoutUseCase` (KMP) to open a new workout session.
    /// 5. Starts the session timer.
    ///
    /// If the KMP use case fails, the camera is stopped, `isTracking` is set
    /// back to `false`, and `lastError` is populated.
    func startTracking() {
        guard !isTracking else {
            #if DEBUG
            print("[PushUpTrackingManager] startTracking() called while already tracking -- ignored")
            #endif
            return
        }

        lastError = nil
        resetDetectionState()
        cameraManager.setupAndStart(position: .front)
        isTracking = true
        sessionStartDate = Date()
        startSessionTimer()

        Task {
            await startKMPWorkout()
        }
    }

    /// Stops the current push-up tracking session.
    ///
    /// 1. Validates that a session is active.
    /// 2. Stops the camera and releases hardware resources synchronously.
    /// 3. Invalidates the session timer synchronously.
    /// 4. Resets `sessionDuration` to `0` immediately.
    /// 5. Calls `FinishWorkoutUseCase` (KMP) to close the workout session.
    func stopTracking() {
        guard isTracking else {
            #if DEBUG
            print("[PushUpTrackingManager] stopTracking() called while not tracking -- ignored")
            #endif
            return
        }

        // Capture session ID before clearing state so the async KMP call
        // below receives the correct value even if stopTracking() is called
        // again before the Task completes.
        let sessionId = activeSessionId

        // All synchronous cleanup happens here, before any async work.
        releaseCameraResources()
        isTracking = false
        activeSessionId = nil
        stopSessionTimer()
        sessionDuration = 0

        Task {
            await finishKMPWorkout(sessionId: sessionId)
        }
    }

    // MARK: - Private: Pipeline Wiring

    /// Wires the delegate chain:
    /// `CameraManager` -> `VisionPoseDetector` -> `PushUpDetector` -> `self`
    private func wireDetectionPipeline() {
        // CameraManager delivers frames to VisionPoseDetector.
        cameraManager.delegate = poseDetector

        // VisionPoseDetector delivers poses to PushUpDetector via a bridge.
        poseDetector.delegate = PoseDetectorBridge(manager: self)

        // PushUpDetector delivers push-up events to self via a bridge.
        pushUpDetector.delegate = PushUpDetectorBridge(manager: self)
    }

    // MARK: - Private: Detection State

    private func resetDetectionState() {
        pushUpDetector.reset()
        currentCount = 0
        currentFormScore = nil
        sessionDuration = 0
        lastPushUpTimestamp = nil
    }

    // MARK: - Private: Camera Resources

    /// Stops the capture session and clears the delegate chain to release
    /// camera hardware and Vision pipeline resources.
    private func releaseCameraResources() {
        cameraManager.stopSession()
        // Clear delegates to break retain cycles and stop frame delivery.
        cameraManager.delegate = nil
        poseDetector.delegate = nil
    }

    // MARK: - Private: Session Timer

    private func startSessionTimer() {
        sessionTimer?.invalidate()
        // The timer is scheduled on the main run loop (this method is
        // main-actor isolated), so the callback fires on the main thread.
        // No additional Task hop is needed.
        sessionTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            guard let self, let start = self.sessionStartDate else { return }
            self.sessionDuration = Date().timeIntervalSince(start)
        }
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    // MARK: - Private: KMP Use Case Calls

    /// Resolves the local user and starts a KMP workout session.
    ///
    /// Called from a background `Task` after the camera has started.
    /// On failure: stops the camera, resets `isTracking`, and sets `lastError`.
    private func startKMPWorkout() async {
        do {
            let user: User = try await withKMPSuspend { handler in
                self.getOrCreateLocalUser.invoke(completionHandler: handler)
            }
            let session: WorkoutSession = try await withKMPSuspend { handler in
                self.startWorkout.invoke(userId: user.id, completionHandler: handler)
            }
            // Only set activeSessionId after both use cases succeed.
            activeSessionId = session.id
            #if DEBUG
            print("[PushUpTrackingManager] KMP workout started: \(session.id)")
            #endif
        } catch {
            #if DEBUG
            print("[PushUpTrackingManager] Failed to start KMP workout: \(error)")
            #endif
            // Camera is already running; stop it and reset tracking state
            // so the user can retry.
            releaseCameraResources()
            isTracking = false
            stopSessionTimer()
            sessionDuration = 0
            lastError = .workoutStartFailed(error.localizedDescription)
        }
    }

    /// Records a single push-up rep in the active KMP workout session.
    ///
    /// Called on the main actor by `PushUpDetectorBridge` after dispatching
    /// from the video output queue.
    private func handlePushUpEvent(_ event: PushUpEvent) {
        guard let sessionId = activeSessionId else {
            // This can happen in the brief window between startTracking() and
            // startKMPWorkout() completing. Silently skip -- the push-up is
            // lost but the session is not corrupted.
            #if DEBUG
            print("[PushUpTrackingManager] handlePushUpEvent: no active session -- skipped")
            #endif
            return
        }

        // Compute duration in milliseconds since the previous push-up.
        // Default to 2000 ms for the first rep (a reasonable average).
        let eventTimestamp = event.timestamp
        let durationMs: Int64
        if let prev = lastPushUpTimestamp, eventTimestamp > prev {
            durationMs = max(1, Int64((eventTimestamp - prev) * 1_000))
        } else {
            durationMs = 2_000
        }
        lastPushUpTimestamp = eventTimestamp

        // Update published state immediately for a responsive UI.
        currentCount = event.count
        currentFormScore = event.formScore?.combinedScore

        // Clamp scores to [0, 1] before passing to KMP to satisfy the
        // `require(depthScore in 0f..1f)` precondition in RecordPushUpUseCase.
        let depthScore = Float(
            (event.formScore?.depthScore ?? 0.5).clamped(to: 0.0...1.0)
        )
        let kmpFormScore = Float(
            (event.formScore?.formScore ?? 0.5).clamped(to: 0.0...1.0)
        )

        Task {
            do {
                _ = try await withKMPSuspend { handler in
                    self.recordPushUp.invoke(
                        sessionId: sessionId,
                        durationMs: durationMs,
                        depthScore: depthScore,
                        formScore: kmpFormScore,
                        completionHandler: handler
                    )
                } as PushUpRecord
                #if DEBUG
                print(
                    "[PushUpTrackingManager] Recorded push-up #\(event.count)" +
                    " depth=\(String(format: "%.2f", depthScore))" +
                    " form=\(String(format: "%.2f", kmpFormScore))"
                )
                #endif
            } catch {
                // A failed record is non-fatal: the push-up count in the UI
                // is already updated. Log and continue.
                #if DEBUG
                print("[PushUpTrackingManager] Failed to record push-up: \(error)")
                #endif
            }
        }
    }

    /// Finishes the KMP workout session.
    ///
    /// Called from a background `Task` after the camera has been stopped and
    /// all synchronous state has been reset.
    private func finishKMPWorkout(sessionId: String?) async {
        guard let sessionId else {
            // startKMPWorkout() never completed (e.g. user stopped immediately).
            // Nothing to finish on the KMP side.
            #if DEBUG
            print("[PushUpTrackingManager] finishKMPWorkout: no active KMP session -- skipped")
            #endif
            return
        }

        do {
            let summary: WorkoutSummary = try await withKMPSuspend { handler in
                self.finishWorkout.invoke(sessionId: sessionId, completionHandler: handler)
            }
            #if DEBUG
            print(
                "[PushUpTrackingManager] KMP workout finished." +
                " push-ups=\(summary.session.pushUpCount)" +
                " credits=\(summary.earnedCredits)"
            )
            #endif
        } catch {
            #if DEBUG
            print("[PushUpTrackingManager] Failed to finish KMP workout: \(error)")
            #endif
            lastError = .workoutFinishFailed(error.localizedDescription)
        }
    }
}

// MARK: - Double + clamped

private extension Double {
    /// Returns the value clamped to the given closed range.
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - KMP Coroutine Bridge

/// Wraps a KMP suspend function (exposed as a `completionHandler`-based callback
/// in Swift) in a Swift `async throws` function using a checked throwing continuation.
///
/// KMP suspend functions are compiled to Swift (via Kotlin/Native Obj-C interop) as:
/// ```swift
/// func invoke(..., completionHandler: @escaping (ReturnType?, Error?) -> Void)
/// ```
/// This helper converts that callback pattern to `async throws`.
///
/// - Parameter body: A closure that receives the continuation callback and
///   must call it exactly once with either a non-nil result or a non-nil error.
/// - Returns: The unwrapped result value.
/// - Throws: The error passed to the continuation, if any.
private func withKMPSuspend<T>(
    _ body: @escaping (@escaping (T?, Error?) -> Void) -> Void
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        body { result, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let result {
                continuation.resume(returning: result)
            } else {
                continuation.resume(
                    throwing: NSError(
                        domain: "PushUpTrackingManager.KMPBridge",
                        code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "KMP suspend function returned nil result with no error"
                        ]
                    )
                )
            }
        }
    }
}

// MARK: - Delegate Bridges

/// Bridges `PoseDetectorDelegate` callbacks (video output queue) to
/// `PushUpTrackingManager`.
///
/// The bridge holds a weak reference to the manager to prevent retain cycles.
/// It is `@unchecked Sendable` because the manager reference is only read
/// (never written) after initialisation, and the bridge only calls
/// `pushUpDetector.process(_:)` which is designed for the video output queue.
private final class PoseDetectorBridge: PoseDetectorDelegate, @unchecked Sendable {

    private weak var manager: PushUpTrackingManager?

    init(manager: PushUpTrackingManager) {
        self.manager = manager
    }

    func poseDetector(_ detector: VisionPoseDetector, didDetect pose: BodyPose?) {
        // Forward to the push-up detector on the video output queue.
        // `PushUpDetector.process(_:)` is designed for this queue.
        manager?.pushUpDetector.process(pose)
    }
}

/// Bridges `PushUpDetectorDelegate` callbacks (video output queue) to
/// `PushUpTrackingManager`.
///
/// The bridge holds a weak reference to the manager to prevent retain cycles.
/// Push-up events are dispatched to the main actor so that `handlePushUpEvent`
/// can safely access main-actor-isolated state.
private final class PushUpDetectorBridge: PushUpDetectorDelegate, @unchecked Sendable {

    private weak var manager: PushUpTrackingManager?

    init(manager: PushUpTrackingManager) {
        self.manager = manager
    }

    func pushUpDetector(_ detector: PushUpDetector, didCount event: PushUpEvent) {
        // Hop to the main actor so the manager can safely update its
        // @Published properties and call KMP use cases.
        Task { @MainActor [weak manager] in
            manager?.handlePushUpEvent(event)
        }
    }
}
