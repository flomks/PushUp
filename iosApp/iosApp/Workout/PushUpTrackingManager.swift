import AVFoundation
import Combine
import Foundation
import Shared

// MARK: - TrackingError

/// Errors that can occur during a push-up tracking session.
///
/// Observe `PushUpTrackingManager.lastError` to react to these in the UI.
enum TrackingError: LocalizedError, Equatable, Sendable {
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
/// - Owns and wires `CameraManager`, `VisionPoseDetector`, `PushUpDetector`,
///   and `PerformanceMonitor`.
/// - On `startTracking()`: requests camera permission, starts the capture session,
///   and calls `StartWorkoutUseCase` (KMP) to create a new workout session.
/// - On each detected push-up: calls `RecordPushUpUseCase` (KMP) with the
///   form scores from `PushUpDetector`.
/// - On `stopTracking()`: stops the camera, releases resources, and calls
///   `FinishWorkoutUseCase` (KMP) to finalise the session.
/// - Publishes `currentCount`, `currentFormScore`, `isTracking`, `sessionDuration`,
///   `activeWarnings`, and `lastError` for SwiftUI consumers.
///
/// **Performance & Battery Optimisation**
/// - `PerformanceMonitor` detects the device tier (iPhone 12+ / iPhone 11 / older)
///   and gates each camera frame through `shouldProcessFrame()` before passing it
///   to Vision. This reduces pose detection frequency on older devices to ~15 FPS
///   (every 2nd frame) or ~10 FPS (every 3rd frame), saving CPU and battery.
/// - Dynamic throttling further increases the skip interval when the measured FPS
///   drops below the tier target (e.g. during thermal throttling).
///
/// **Auto-Stop on Background**
/// - `CameraManager` already stops the `AVCaptureSession` when the app enters the
///   background. `PerformanceMonitor` additionally pauses frame processing so that
///   any frames delivered in the brief window before the session stops are ignored.
/// - When the app returns to the foreground, `CameraManager` restarts the session
///   and `PerformanceMonitor` resumes frame processing automatically.
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
/// - Bridge objects are strongly retained by the manager and released on stop.
///
/// **Usage**
/// ```swift
/// // Requires KoinIOSKt.doInitKoin() to have been called at app startup.
/// let manager = PushUpTrackingManager()
/// manager.startTracking()
///
/// // Observe published properties via SwiftUI or Combine:
/// manager.$currentCount
///     .sink { count in print("Push-ups: \(count)") }
///     .store(in: &cancellables)
///
/// // Always call stopTracking() before releasing the manager.
/// manager.stopTracking()
/// ```
@MainActor
final class PushUpTrackingManager: ObservableObject {

    // MARK: - Published State

    /// Total push-ups counted in the current session.
    @Published private(set) var currentCount: Int = 0

    /// The combined form score (0.0-1.0) of the most recently completed push-up,
    /// or `nil` when no push-up has been counted yet in this session.
    @Published private(set) var currentFormScore: Double? = nil

    /// `true` while a tracking session is active (camera running + KMP session open).
    @Published private(set) var isTracking: Bool = false

    /// Elapsed time of the current session in seconds. `0` when not tracking.
    @Published private(set) var sessionDuration: TimeInterval = 0

    /// The most recent error, or `nil` when the last operation succeeded.
    /// Reset to `nil` at the start of each `startTracking()` call.
    @Published private(set) var lastError: TrackingError? = nil

    /// Active edge-case warnings from the most recently processed frame.
    /// Empty when conditions are good. Updated on the main queue.
    @Published private(set) var activeWarnings: [EdgeCaseWarning] = []

    // MARK: - Private: Camera & Detection Pipeline

    private let cameraManager: CameraManager
    private let poseDetector: VisionPoseDetector
    private let pushUpDetector: PushUpDetector

    /// Performance monitor: gates frame processing based on device tier and
    /// measured FPS. Also pauses processing when the app is backgrounded.
    /// Exposed as read-only for SwiftUI consumers that need to display FPS
    /// or device tier information.
    private(set) var performanceMonitor: PerformanceMonitor

    /// Strong references to the delegate bridges. `CameraManager.delegate`,
    /// `VisionPoseDetector.delegate`, and `PushUpDetector.delegate` are all
    /// `weak`, so the manager must hold strong references to keep the bridges
    /// alive for the duration of a tracking session.
    private var poseDetectorBridge: PoseDetectorBridge?
    private var pushUpDetectorBridge: PushUpDetectorBridge?

    // MARK: - Private: KMP Use Cases

    private let getCurrentUser: GetCurrentUserUseCase
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

    /// The `Task` running `startKMPWorkout()`. Stored so that `stopTracking()`
    /// can cancel it to prevent an orphaned KMP session if the user stops
    /// before the KMP workout has been created.
    private var startWorkoutTask: Task<Void, Never>?

    // MARK: - Init

    /// Creates a manager with explicit use-case dependencies.
    ///
    /// Use this initialiser in tests or when you want to supply mock use cases.
    ///
    /// - Parameters:
    ///   - cameraManager: The camera manager to use. Defaults to a new instance.
    ///   - poseDetector: The Vision pose detector. Defaults to a new instance.
    ///   - pushUpDetector: The push-up detector. Defaults to a new instance.
    ///   - performanceMonitor: The performance monitor. Defaults to a new instance.
    ///   - getCurrentUser: Use case for resolving the authenticated user ID.
    ///   - startWorkout: Use case for starting a KMP workout session.
    ///   - recordPushUp: Use case for recording a single push-up rep.
    ///   - finishWorkout: Use case for finishing the KMP workout session.
    init(
        cameraManager: CameraManager = CameraManager(),
        poseDetector: VisionPoseDetector = VisionPoseDetector(),
        pushUpDetector: PushUpDetector = PushUpDetector(),
        performanceMonitor: PerformanceMonitor,
        getCurrentUser: GetCurrentUserUseCase,
        startWorkout: StartWorkoutUseCase,
        recordPushUp: RecordPushUpUseCase,
        finishWorkout: FinishWorkoutUseCase
    ) {
        self.cameraManager = cameraManager
        self.poseDetector = poseDetector
        self.pushUpDetector = pushUpDetector
        self.performanceMonitor = performanceMonitor
        self.getCurrentUser = getCurrentUser
        self.startWorkout = startWorkout
        self.recordPushUp = recordPushUp
        self.finishWorkout = finishWorkout
    }

    /// Convenience initialiser that resolves use cases from the Koin DI graph.
    ///
    /// Requires `KoinIOSKt.doInitKoin()` to have been called at app startup
    /// before this initialiser is invoked.
    convenience init() {
        let helper = DIHelper.shared
        self.init(
            performanceMonitor: PerformanceMonitor(),
            getCurrentUser: helper.getCurrentUserUseCase(),
            startWorkout: helper.startWorkoutUseCase(),
            recordPushUp: helper.recordPushUpUseCase(),
            finishWorkout: helper.finishWorkoutUseCase()
        )
    }

    /// `deinit` of a `@MainActor`-isolated class runs on the main actor in
    /// Swift 5.9+, so it is safe to access `sessionTimer` directly and
    /// invalidate it without dispatching to another queue.
    ///
    /// `stopTracking()` always invalidates and nils the timer synchronously,
    /// so this is a safety-net for callers that release the manager without
    /// calling `stopTracking()` first.
    deinit {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    // MARK: - Public API

    /// Starts a push-up tracking session.
    ///
    /// 1. Validates that no session is already active.
    /// 2. Resets the detection pipeline and clears any previous error.
    /// 3. Wires the delegate chain (camera -> pose detector -> push-up detector).
    /// 4. Starts the camera if it is not already running (e.g. from `startCameraPreview`).
    ///    If the camera is already running from the idle preview, we reuse the existing
    ///    session to avoid reconfiguring a live `AVCaptureSession`, which causes a crash
    ///    on iOS when inputs/outputs are removed and re-added while the session is running.
    /// 5. Calls `StartWorkoutUseCase` (KMP) to open a new workout session.
    /// 6. Starts the session timer.
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

        // (Re-)wire the delegate chain. This must happen on every start because
        // stopTracking() clears the delegates to release camera resources.
        wireDetectionPipeline()

        // If the camera is already running from the idle preview (startCameraPreview),
        // reuse the existing session instead of calling setupAndStart() again.
        // Calling setupAndStart() on a running session triggers configureSession(),
        // which removes and re-adds the shared videoOutput while the session is live,
        // causing an AVFoundation crash on iOS.
        if cameraManager.state != .running {
            cameraManager.setupAndStart(position: FacingDirection.front)
        }

        isTracking = true
        sessionStartDate = Date()
        startSessionTimer()

        startWorkoutTask = Task {
            await startKMPWorkout()
        }
    }

    /// Stops the current push-up tracking session.
    ///
    /// 1. Validates that a session is active.
    /// 2. Cancels any in-flight KMP startup task.
    /// 3. Stops the camera and releases hardware resources synchronously.
    /// 4. Invalidates the session timer synchronously.
    /// 5. Resets `sessionDuration` to `0` immediately.
    /// 6. Calls `FinishWorkoutUseCase` (KMP) to close the workout session.
    func stopTracking() {
        guard isTracking else {
            #if DEBUG
            print("[PushUpTrackingManager] stopTracking() called while not tracking -- ignored")
            #endif
            return
        }

        // Cancel the startup task to prevent an orphaned KMP session if the
        // user stops before startKMPWorkout() has completed.
        startWorkoutTask?.cancel()
        startWorkoutTask = nil

        // Capture session ID before clearing state so the async KMP call
        // below receives the correct value.
        let sessionId = activeSessionId

        // All synchronous cleanup happens here, before any async work.
        releaseCameraResources()
        isTracking = false
        activeSessionId = nil
        stopSessionTimer()
        sessionDuration = 0
        activeWarnings = []

        Task {
            await finishKMPWorkout(sessionId: sessionId)
        }
    }

    // MARK: - Workout Screen Accessors

    /// The preview layer for the camera feed. Read-only access for the
    /// workout view to display the live camera preview.
    var previewLayer: AVCaptureVideoPreviewLayer {
        cameraManager.previewLayer
    }

    /// The current camera state. Published by `CameraManager`.
    var cameraState: CameraState {
        cameraManager.state
    }

    /// The current camera position (front/back).
    var currentFacingDirection: FacingDirection {
        cameraManager.currentPosition
    }

    /// Switches between front and back camera.
    func switchCamera() {
        cameraManager.switchCamera()
    }

    /// Starts the camera preview without starting the tracking pipeline.
    /// Use this to show the camera feed in the idle state before the user
    /// taps "Start".
    func startCameraPreview(position: FacingDirection = FacingDirection.front) {
        guard !isTracking else { return }
        cameraManager.setupAndStart(position: position)
    }

    /// Stops the camera preview. Only effective when not tracking.
    func stopCameraPreview() {
        guard !isTracking else { return }
        cameraManager.stopSession()
    }

    /// Publisher for camera state changes.
    var cameraStatePublisher: Published<CameraState>.Publisher {
        cameraManager.$state
    }

    /// Publisher for camera position changes.
    var cameraPositionPublisher: Published<FacingDirection>.Publisher {
        cameraManager.$currentPosition
    }

    /// Publisher for the most recently detected pose, updated on the main
    /// queue by `VisionPoseDetector`. Safe to observe from SwiftUI views.
    /// `nil` when no person is detected or tracking is not active.
    var currentPosePublisher: Published<BodyPose?>.Publisher {
        poseDetector.$currentPose
    }

    // MARK: - Private: Pipeline Wiring

    /// Wires the delegate chain:
    /// `CameraManager` -> `PerformanceMonitorBridge` -> `VisionPoseDetector` -> `PushUpDetector` -> `self`
    ///
    /// The `PerformanceMonitorBridge` sits between the camera and the pose
    /// detector. It calls `performanceMonitor.shouldProcessFrame()` on every
    /// incoming frame and only forwards frames that should be processed.
    ///
    /// Creates new bridge objects and stores strong references to them. The
    /// bridges hold weak references back to the manager to prevent retain cycles.
    private func wireDetectionPipeline() {
        // CameraManager delivers frames to a PerformanceMonitorBridge that
        // gates frames based on the device tier and measured FPS.
        let perfBridge = PerformanceMonitorBridge(
            monitor: performanceMonitor,
            poseDetector: poseDetector
        )
        cameraManager.delegate = perfBridge
        // Keep a strong reference so the bridge is not deallocated while
        // the camera session is running.
        _performanceMonitorBridge = perfBridge

        // VisionPoseDetector delivers poses to PushUpDetector via a bridge.
        // The bridge captures `pushUpDetector` directly to avoid accessing
        // a @MainActor-isolated property from the video output queue.
        let poseBridge = PoseDetectorBridge(pushUpDetector: pushUpDetector, manager: self)
        poseDetectorBridge = poseBridge
        poseDetector.delegate = poseBridge

        // PushUpDetector delivers push-up events to self via a bridge.
        let pushUpBridge = PushUpDetectorBridge(manager: self)
        pushUpDetectorBridge = pushUpBridge
        pushUpDetector.delegate = pushUpBridge
    }

    /// Strong reference to the performance monitor bridge (camera -> pose detector).
    private var _performanceMonitorBridge: PerformanceMonitorBridge?

    // MARK: - Private: Detection State

    private func resetDetectionState() {
        pushUpDetector.reset()
        poseDetector.reset()
        performanceMonitor.reset()
        currentCount = 0
        currentFormScore = nil
        sessionDuration = 0
        lastPushUpTimestamp = nil
        activeWarnings = []
    }

    // MARK: - Private: Camera Resources

    /// Stops the capture session and clears the delegate chain to release
    /// camera hardware and Vision pipeline resources. Also releases the
    /// strong references to bridge objects.
    private func releaseCameraResources() {
        cameraManager.stopSession()
        // Clear delegates to break retain cycles and stop frame delivery.
        cameraManager.delegate = nil
        poseDetector.delegate = nil
        pushUpDetector.delegate = nil
        // Release bridge objects.
        _performanceMonitorBridge = nil
        poseDetectorBridge = nil
        pushUpDetectorBridge = nil
    }

    // MARK: - Private: Session Timer

    private func startSessionTimer() {
        sessionTimer?.invalidate()
        // The timer is scheduled on the main run loop (this method is
        // main-actor isolated), so the callback fires on the main thread.
        // `MainActor.assumeIsolated` makes the actor isolation explicit for
        // Swift 6 strict concurrency compliance.
        sessionTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let start = self.sessionStartDate else { return }
                self.sessionDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    // MARK: - Private: Warning Updates

    /// Called by `PoseDetectorBridge` when warnings change.
    /// Main-actor isolated.
    fileprivate func handleWarnings(_ warnings: [EdgeCaseWarning]) {
        activeWarnings = warnings
    }

    // MARK: - Private: KMP Use Case Calls

    /// Resolves the authenticated user and starts a KMP workout session.
    ///
    /// Called from a cancellable `Task` after the camera has started.
    /// On failure: stops the camera, resets `isTracking`, and sets `lastError`.
    /// On cancellation: returns early without setting `activeSessionId`.
    ///
    /// **Idempotency:** `StartWorkoutUseCase` returns the existing active session
    /// when one is already open (e.g. after an app crash). The session ID is
    /// stored in `activeSessionId` regardless of whether it is new or resumed.
    private func startKMPWorkout() async {
        do {
            // GetCurrentUserUseCase returns User? (nullable). Use the nullable
            // variant of withKMPSuspend so that a nil result (not logged in)
            // is surfaced as a clear "not authenticated" error rather than a
            // generic "nil result with no error" KMPBridge error.
            guard let user: User = try await withKMPSuspendOptional({ handler in
                self.getCurrentUser.invoke(completionHandler: handler)
            }) else {
                throw NSError(
                    domain: "PushUpTrackingManager",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "No authenticated user found. Please log in."]
                )
            }

            // Check cancellation between the two KMP calls. If stopTracking()
            // was called while getCurrentUser was in flight, we must not
            // start a new workout session.
            try Task.checkCancellation()

            let session = try await withKMPSuspend { handler in
                self.startWorkout.invoke(userId: user.id, completionHandler: handler)
            } as Shared.WorkoutSession

            // Final cancellation check before committing the session ID.
            guard !Task.isCancelled else { return }

            activeSessionId = session.id
            #if DEBUG
            print("[PushUpTrackingManager] KMP workout started: session=\(session.id)")
            #endif
        } catch is CancellationError {
            // stopTracking() cancelled us. No cleanup needed -- stopTracking()
            // already handled everything.
            #if DEBUG
            print("[PushUpTrackingManager] startKMPWorkout cancelled")
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
    fileprivate func handlePushUpEvent(_ event: PushUpEvent) {
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
        // If timestamps go backwards (e.g. during camera switch), the default
        // is used to avoid negative or zero durations.
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

        // Capture use case reference to avoid strong self in the closure.
        let useCase = self.recordPushUp

        Task {
            do {
                _ = try await withKMPSuspend { handler in
                    useCase.invoke(
                        sessionId: sessionId,
                        durationMs: durationMs,
                        depthScore: depthScore,
                        formScore: kmpFormScore,
                        completionHandler: handler
                    )
                } as Shared.PushUpRecord
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
            let summary = try await withKMPSuspend { handler in
                self.finishWorkout.invoke(sessionId: sessionId, completionHandler: handler)
            } as Shared.WorkoutSummary
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
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
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
/// **Double-resume protection**: The completion handler may be called more than
/// once in certain Kotlin/Native interop edge cases (e.g. coroutine cancellation).
/// An `NSLock`-protected flag ensures the continuation is resumed exactly once.
///
/// - Parameter body: A closure that receives the continuation callback and
///   must call it at least once with either a non-nil result or a non-nil error.
/// - Returns: The unwrapped result value.
/// - Throws: The error passed to the continuation, if any.
private func withKMPSuspend<T>(
    _ body: @escaping (@escaping (T?, Error?) -> Void) -> Void
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let lock = NSLock()
        var hasResumed = false

        body { result, error in
            lock.lock()
            guard !hasResumed else {
                lock.unlock()
                #if DEBUG
                print("[KMPBridge] WARNING: completion handler called more than once -- ignored")
                #endif
                return
            }
            hasResumed = true
            lock.unlock()

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

/// Variant of `withKMPSuspend` for KMP suspend functions that return a nullable
/// type (`T?`). Returns `nil` when the KMP function completes with no result and
/// no error (e.g. `GetCurrentUserUseCase` when no user is logged in), instead of
/// throwing a "nil result with no error" error.
///
/// Use this when the KMP function legitimately returns `null` as a valid result.
private func withKMPSuspendOptional<T>(
    _ body: @escaping (@escaping (T?, Error?) -> Void) -> Void
) async throws -> T? {
    try await withCheckedThrowingContinuation { continuation in
        let lock = NSLock()
        var hasResumed = false

        body { result, error in
            lock.lock()
            guard !hasResumed else {
                lock.unlock()
                #if DEBUG
                print("[KMPBridge] WARNING: completion handler called more than once -- ignored")
                #endif
                return
            }
            hasResumed = true
            lock.unlock()

            if let error {
                continuation.resume(throwing: error)
            } else {
                // result may be nil (e.g. no logged-in user) -- that is valid here.
                continuation.resume(returning: result)
            }
        }
    }
}

// MARK: - Delegate Bridges

/// Bridges `CameraManagerDelegate` callbacks (video output queue) to
/// `VisionPoseDetector`, gating frames through `PerformanceMonitor`.
///
/// This bridge sits between `CameraManager` and `VisionPoseDetector`. For each
/// incoming frame it:
/// 1. Calls `monitor.shouldProcessFrame()` to decide whether to skip the frame.
/// 2. If the frame should be processed, forwards it to `poseDetector.process(_:)`.
/// 3. Calls `monitor.recordPoseDetectionCompleted()` after Vision returns.
///
/// `@unchecked Sendable` is safe because both `monitor` and `poseDetector` are
/// immutable references to thread-safe objects.
private final class PerformanceMonitorBridge: CameraManagerDelegate, @unchecked Sendable {

    private let monitor: PerformanceMonitor
    private let poseDetector: VisionPoseDetector

    init(monitor: PerformanceMonitor, poseDetector: VisionPoseDetector) {
        self.monitor = monitor
        self.poseDetector = poseDetector
    }

    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        guard monitor.shouldProcessFrame() else { return }
        poseDetector.process(sampleBuffer)
        monitor.recordPoseDetectionCompleted()
    }
}

/// Bridges `PoseDetectorDelegate` callbacks (video output queue) to
/// `PushUpDetector` and forwards edge-case warnings to the manager.
///
/// Captures a direct reference to the `PushUpDetector` at creation time so
/// that `process(_:)` can be called on the video output queue without crossing
/// the main-actor isolation boundary. The manager is held weakly to prevent
/// retain cycles; warnings are dispatched to the main actor.
///
/// `@unchecked Sendable` is safe because `pushUpDetector` is an immutable
/// reference to a `final class` whose `process(_:)` method is designed for
/// the video output queue.
private final class PoseDetectorBridge: PoseDetectorDelegate, @unchecked Sendable {

    private let pushUpDetector: PushUpDetector
    private weak var manager: PushUpTrackingManager?

    /// Cached copy of the last forwarded warnings to avoid dispatching a
    /// main-actor `Task` on every frame when warnings have not changed.
    /// Only accessed from the video output queue (single-writer).
    private var _lastWarnings: [EdgeCaseWarning] = []

    init(pushUpDetector: PushUpDetector, manager: PushUpTrackingManager) {
        self.pushUpDetector = pushUpDetector
        self.manager = manager
    }

    func poseDetector(
        _ detector: VisionPoseDetector,
        didDetect pose: BodyPose?,
        warnings: [EdgeCaseWarning]
    ) {
        pushUpDetector.process(pose)

        // Only dispatch to the main actor when warnings actually changed.
        // At 30 FPS this avoids ~30 unnecessary Task allocations per second
        // during normal operation when warnings are stable.
        guard warnings != _lastWarnings else { return }
        _lastWarnings = warnings
        Task { @MainActor [weak manager] in
            manager?.handleWarnings(warnings)
        }
    }
}

/// Bridges `PushUpDetectorDelegate` callbacks (video output queue) to
/// `PushUpTrackingManager`.
///
/// Holds a weak reference to the manager to prevent retain cycles.
/// Push-up events are dispatched to the main actor so that `handlePushUpEvent`
/// can safely access main-actor-isolated state.
private final class PushUpDetectorBridge: PushUpDetectorDelegate, @unchecked Sendable {

    private weak var manager: PushUpTrackingManager?

    init(manager: PushUpTrackingManager) {
        self.manager = manager
    }

    func pushUpDetector(_ detector: PushUpDetector, didCount event: PushUpEvent) {
        Task { @MainActor [weak manager] in
            manager?.handlePushUpEvent(event)
        }
    }
}
