import AVFoundation
import Combine
import Foundation
import shared

// MARK: - TrackingError

/// Errors that can occur during a push-up tracking session.
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
/// - Publishes `currentCount`, `currentFormScore`, `isTracking`, and
///   `sessionDuration` for SwiftUI consumers.
///
/// **Threading model**
/// - All `@Published` properties are updated on the **main queue**.
/// - Camera frames and pose/push-up detection run on the video output queue.
/// - KMP use-case calls are dispatched to a background `Task` and their
///   results are marshalled back to the main actor.
///
/// **Memory management**
/// - `stopTracking()` stops the `AVCaptureSession` and clears the delegate
///   chain, releasing the camera hardware and Vision pipeline.
/// - The session timer is invalidated on stop to prevent retain cycles.
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

    // MARK: - Private: Camera & Detection Pipeline

    private let cameraManager: CameraManager
    private let poseDetector: VisionPoseDetector

    /// Accessed from the video output queue (via `PushUpDetectorBridge`) and
    /// from the main actor (via `stopTracking`). The two call sites are
    /// serialised by the app's usage pattern (stop is only called when no
    /// frame is being processed), so `nonisolated(unsafe)` is correct here.
    nonisolated(unsafe) private let pushUpDetector: PushUpDetector

    // MARK: - Private: KMP Use Cases

    private let getOrCreateLocalUser: GetOrCreateLocalUserUseCase
    private let startWorkout: StartWorkoutUseCase
    private let recordPushUp: RecordPushUpUseCase
    private let finishWorkout: FinishWorkoutUseCase

    // MARK: - Private: Session State

    /// The KMP session ID returned by `StartWorkoutUseCase`. Non-nil while tracking.
    private var activeSessionId: String? = nil

    /// Timestamp when the current session started. Used to compute `sessionDuration`.
    private var sessionStartDate: Date? = nil

    /// Timer that fires every second to update `sessionDuration`.
    private var sessionTimer: Timer? = nil

    /// Timestamp of the most recently counted push-up (seconds since device boot,
    /// from `PushUpEvent.timestamp`). Used to compute `durationMs` for
    /// `RecordPushUpUseCase`. Protected by main-actor isolation.
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

    deinit {
        sessionTimer?.invalidate()
    }

    // MARK: - Public API

    /// Starts a push-up tracking session.
    ///
    /// 1. Validates that no session is already active.
    /// 2. Resets the detection pipeline.
    /// 3. Starts the camera (requests permission if needed).
    /// 4. Calls `StartWorkoutUseCase` (KMP) to open a new workout session.
    /// 5. Starts the session timer.
    ///
    /// If the camera fails to start, `isTracking` remains `false` and the
    /// camera error is surfaced via `CameraManager.state`.
    ///
    /// If the KMP use case fails, the camera is stopped and `isTracking` is
    /// set back to `false`.
    func startTracking() {
        guard !isTracking else {
            #if DEBUG
            print("[PushUpTrackingManager] startTracking() called while already tracking -- ignored")
            #endif
            return
        }

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
    /// 2. Stops the camera and releases hardware resources.
    /// 3. Invalidates the session timer.
    /// 4. Calls `FinishWorkoutUseCase` (KMP) to close the workout session.
    /// 5. Resets all published state.
    func stopTracking() {
        guard isTracking else {
            #if DEBUG
            print("[PushUpTrackingManager] stopTracking() called while not tracking -- ignored")
            #endif
            return
        }

        // Stop camera and release hardware resources immediately.
        releaseCameraResources()

        // Capture session ID before clearing state.
        let sessionId = activeSessionId

        // Reset tracking flag and timer.
        isTracking = false
        stopSessionTimer()

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
        sessionTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.sessionStartDate else { return }
                self.sessionDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    // MARK: - Private: KMP Use Case Calls

    /// Resolves the local user and starts a KMP workout session.
    /// Called from a background `Task` after the camera has started.
    private func startKMPWorkout() async {
        do {
            let user: User = try await withKMPSuspend { handler in
                self.getOrCreateLocalUser.invoke(completionHandler: handler)
            }
            let session: WorkoutSession = try await withKMPSuspend { handler in
                self.startWorkout.invoke(userId: user.id, completionHandler: handler)
            }
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
        }
    }

    /// Records a single push-up rep in the active KMP workout session.
    ///
    /// Called on the main actor after being dispatched from the video output
    /// queue via `PushUpDetectorBridge`.
    func handlePushUpEvent(_ event: PushUpEvent) {
        guard let sessionId = activeSessionId else {
            #if DEBUG
            print("[PushUpTrackingManager] handlePushUpEvent: no active session -- skipped")
            #endif
            return
        }

        // Compute duration in milliseconds since the previous push-up
        // (or a default of 2000 ms for the first rep).
        let eventTimestamp = event.timestamp
        let durationMs: Int64
        if let prev = lastPushUpTimestamp, eventTimestamp > prev {
            durationMs = Int64((eventTimestamp - prev) * 1_000)
        } else {
            durationMs = 2_000
        }
        lastPushUpTimestamp = eventTimestamp

        // Update published state immediately for responsive UI.
        currentCount = event.count
        currentFormScore = event.formScore?.combinedScore

        // Map form scores to KMP types (Float in [0, 1]).
        let depthScore = Float(event.formScore?.depthScore ?? 0.5)
        let kmpFormScore = Float(event.formScore?.formScore ?? 0.5)

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
                print("[PushUpTrackingManager] Recorded push-up #\(event.count) (form: \(String(format: "%.2f", kmpFormScore)))")
                #endif
            } catch {
                #if DEBUG
                print("[PushUpTrackingManager] Failed to record push-up: \(error)")
                #endif
            }
        }
    }

    /// Finishes the KMP workout session.
    /// Called from a background `Task` after the camera has been stopped.
    private func finishKMPWorkout(sessionId: String?) async {
        guard let sessionId else {
            #if DEBUG
            print("[PushUpTrackingManager] finishKMPWorkout: no session ID -- skipped")
            #endif
            activeSessionId = nil
            sessionDuration = 0
            return
        }

        do {
            let summary: WorkoutSummary = try await withKMPSuspend { handler in
                self.finishWorkout.invoke(sessionId: sessionId, completionHandler: handler)
            }
            #if DEBUG
            print("[PushUpTrackingManager] KMP workout finished. Push-ups: \(summary.session.pushUpCount), Credits: \(summary.earnedCredits)")
            #endif
        } catch {
            #if DEBUG
            print("[PushUpTrackingManager] Failed to finish KMP workout: \(error)")
            #endif
        }

        activeSessionId = nil
        sessionDuration = 0
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
/// (never written) after initialisation, and the bridge only calls the
/// `nonisolated(unsafe)` `pushUpDetector` property on it.
private final class PoseDetectorBridge: PoseDetectorDelegate, @unchecked Sendable {

    private weak var manager: PushUpTrackingManager?

    init(manager: PushUpTrackingManager) {
        self.manager = manager
    }

    func poseDetector(_ detector: VisionPoseDetector, didDetect pose: BodyPose?) {
        // Forward to the push-up detector. This runs on the video output queue.
        // `pushUpDetector` is `nonisolated(unsafe)` and designed for this queue.
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
        // Dispatch to the main actor so the manager can safely update its
        // @Published properties and call KMP use cases.
        Task { @MainActor [weak manager] in
            manager?.handlePushUpEvent(event)
        }
    }
}
