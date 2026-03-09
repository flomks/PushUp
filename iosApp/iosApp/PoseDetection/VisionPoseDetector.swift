import AVFoundation
import CoreMedia
import Vision

// MARK: - PoseDetectorDelegate

/// Receives pose detection results on the caller's queue (typically the
/// camera's `videoOutputQueue`).
///
/// Implementations must be non-blocking. Dispatch UI updates to the main queue.
///
/// Marked `Sendable` because instances are set from the main queue and called
/// from the video output queue.
protocol PoseDetectorDelegate: AnyObject, Sendable {
    /// Called after every successfully processed frame.
    /// - Parameters:
    ///   - detector: The detector that produced the result.
    ///   - pose: The detected `BodyPose`, or `nil` when no person was found.
    ///   - warnings: Active edge-case warnings for this frame (may be empty).
    func poseDetector(
        _ detector: VisionPoseDetector,
        didDetect pose: BodyPose?,
        warnings: [EdgeCaseWarning]
    )
}

// MARK: - VisionPoseDetector

/// Processes `CMSampleBuffer` video frames using `VNDetectHumanBodyPoseRequest`
/// and publishes `BodyPose` snapshots at up to 30 FPS.
///
/// **Edge-case handling**
/// All observations returned by Vision (potentially multiple people) are passed
/// through an `EdgeCaseHandler` which:
/// - Selects the largest/most-confident person when multiple are detected.
/// - Emits `EdgeCaseWarning` values for no-person, poor angle, and poor lighting.
/// - Applies hysteresis so warnings don't flicker on transient single-frame drops.
///
/// Active warnings are published via `activeWarnings` and delivered to the
/// delegate alongside the selected pose.
///
/// **Threading model**
/// - `process(_:)` is designed to be called from `CameraManager`'s
///   `videoOutputQueue` (`.userInteractive` QoS).
/// - All Vision work runs synchronously on the calling queue so that the
///   result is available within the same frame budget.
/// - `delegate` callbacks are delivered on the same queue as `process(_:)`.
/// - The `@Published` properties are always updated on the **main queue**.
///
/// **Performance**
/// `VNDetectHumanBodyPoseRequest` is designed for real-time use and typically
/// completes in 5-20 ms on A12+ chips. The detector skips frames when the
/// previous request has not yet finished to stay within the 33 ms budget.
///
/// **Usage**
/// ```swift
/// let detector = VisionPoseDetector()
/// detector.delegate = self
///
/// // Inside CameraManagerDelegate:
/// func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
///     detector.process(sampleBuffer)
/// }
/// ```
final class VisionPoseDetector: ObservableObject, @unchecked Sendable {

    // MARK: - Published State

    /// The most recently detected pose, updated on the main queue.
    /// `nil` when no person is visible or detection is paused.
    ///
    /// Thread safety: only written on the main queue via `DispatchQueue.main.async`
    /// in `deliverResult`. The `@unchecked Sendable` conformance is safe because
    /// all mutable state is protected by locks or confined to a single queue.
    @Published private(set) var currentPose: BodyPose?

    /// Active edge-case warnings for the most recently processed frame.
    /// Updated on the main queue alongside `currentPose`.
    @Published private(set) var activeWarnings: [EdgeCaseWarning] = []

    // MARK: - Delegate (thread-safe)

    /// Protected by `delegateLock` so it can be set from the main queue and
    /// read safely from the video output queue inside `deliverResult`.
    private let delegateLock = NSLock()
    private weak var _delegate: PoseDetectorDelegate?

    var delegate: PoseDetectorDelegate? {
        get {
            delegateLock.lock()
            defer { delegateLock.unlock() }
            return _delegate
        }
        set {
            delegateLock.lock()
            defer { delegateLock.unlock() }
            _delegate = newValue
        }
    }

    // MARK: - Configuration (thread-safe)

    /// When `true`, the detector processes every incoming frame.
    /// Set to `false` to pause detection without stopping the camera.
    ///
    /// Thread-safe: reads and writes are protected by `stateLock`.
    var isEnabled: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isEnabled
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _isEnabled = newValue
        }
    }

    // MARK: - Private State

    /// Lock protecting `_isEnabled`, `_isProcessing`, and `_frameCount`.
    ///
    /// Uses `NSLock` for compatibility. These fields are read/written from
    /// different queues (main queue sets `isEnabled`, video output queue
    /// reads it and toggles `isProcessing`/`_frameCount`).
    private let stateLock = NSLock()
    private var _isEnabled: Bool = true
    private var _isProcessing: Bool = false

    /// Monotonically increasing frame counter used for debug logging.
    /// Protected by `stateLock` to prevent data races.
    private var _frameCount: UInt64 = 0

    /// Edge-case handler. Called on the video output queue; not thread-safe,
    /// but that is fine because `process(_:)` is serialised by `_isProcessing`.
    private let edgeCaseHandler: EdgeCaseHandler

    // MARK: - Init

    /// Creates a detector with the given edge-case handler configuration.
    ///
    /// - Parameter edgeCaseConfiguration: Thresholds for the `EdgeCaseHandler`.
    ///   Defaults to `EdgeCaseHandler.Configuration.default`.
    init(edgeCaseConfiguration: EdgeCaseHandler.Configuration = .default) {
        self.edgeCaseHandler = EdgeCaseHandler(configuration: edgeCaseConfiguration)
    }

    // MARK: - Public API

    /// Submits `sampleBuffer` to Vision for body pose detection.
    ///
    /// This method is **synchronous** and should be called from a background
    /// queue (e.g. `CameraManager`'s `videoOutputQueue`). It returns quickly
    /// when `isEnabled == false` or when a previous frame is still being
    /// processed.
    ///
    /// - Parameters:
    ///   - sampleBuffer: A video frame delivered by `AVCaptureOutput`.
    ///   - cameraPosition: The active camera lens. Used to derive the correct
    ///     `CGImagePropertyOrientation` for the raw sensor pixel buffer.
    ///     Defaults to `.back` for backward compatibility.
    func process(_ sampleBuffer: CMSampleBuffer, cameraPosition: CapturePosition = .back) {
        // Acquire lock to check both flags atomically, set isProcessing,
        // and increment frame counter under the same critical section.
        stateLock.lock()
        guard _isEnabled, !_isProcessing else {
            stateLock.unlock()
            return
        }
        _isProcessing = true
        _frameCount &+= 1
        let currentFrame = _frameCount
        stateLock.unlock()

        defer {
            stateLock.lock()
            _isProcessing = false
            stateLock.unlock()
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // Obtain the pixel buffer.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            let result = edgeCaseHandler.evaluate(nil, allPoses: [])
            deliverResult(result.selectedPose, warnings: result.warnings)
            return
        }

        // Determine the correct orientation to pass to Vision.
        //
        // CameraManager applies two transforms to the video output connection:
        //   1. Rotation to portrait (videoRotationAngle=90 on iOS 17+,
        //      videoOrientation=.portrait on iOS 16)
        //   2. Horizontal mirroring for the front camera (isVideoMirrored=true)
        //
        // On iOS 17+, videoRotationAngle physically rotates the CVPixelBuffer
        // to portrait AND isVideoMirrored physically mirrors the pixels.
        // The buffer we receive is already portrait and already mirrored.
        // Vision must receive .up (NOT .upMirrored — the buffer is pre-mirrored).
        //
        // On iOS 16, videoOrientation=.portrait does NOT rotate the raw buffer
        // (only the preview layer). But isVideoMirrored DOES mirror the pixels.
        // The buffer is landscape-right and pre-mirrored for front camera.
        // Vision must receive .right (NOT .leftMirrored — already mirrored).
        //
        // In both cases: the front camera buffer is already mirrored by
        // AVFoundation, so we must NOT tell Vision to mirror again.
        let orientation: CGImagePropertyOrientation = {
            let width  = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            if height > width {
                // Portrait buffer (iOS 17+ with videoRotationAngle=90)
                // Already mirrored for front camera → always .up
                return .up
            } else {
                // Landscape buffer (iOS 16 native sensor orientation)
                // Already mirrored for front camera → always .right
                return .right
            }
        }()

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )

        // Create a fresh request per frame. While VNRequest can be reused
        // when access is serialised, creating per-frame avoids subtle bugs
        // if the serialisation invariant is ever relaxed, and the allocation
        // cost (~microseconds) is negligible vs. the ~10 ms inference time.
        let request = VNDetectHumanBodyPoseRequest()

        do {
            #if DEBUG
            let start = CACurrentMediaTime()
            #endif

            try handler.perform([request])

            #if DEBUG
            let elapsed = (CACurrentMediaTime() - start) * 1_000
            if currentFrame % 30 == 0 {
                // Log every 30 frames (~1 s at 30 FPS) to avoid log spam.
                print("[VisionPoseDetector] frame \(currentFrame): \(String(format: "%.1f", elapsed)) ms")
            }
            #endif

            // Build poses for ALL observations (multiple people in frame).
            let observations = request.results ?? []
            let allPoses = observations.map { buildPose(from: $0, timestamp: timestamp) }

            // Primary pose (first observation) for backward compatibility.
            let primaryPose = allPoses.first

            // Apply edge-case logic: select the best pose, emit warnings.
            let result = edgeCaseHandler.evaluate(primaryPose, allPoses: allPoses)

            #if DEBUG
            if !result.warnings.isEmpty && currentFrame % 30 == 0 {
                print("[VisionPoseDetector] warnings: \(result.warnings.map(\.description).joined(separator: ", "))")
            }
            #endif

            deliverResult(result.selectedPose, warnings: result.warnings)

        } catch {
            #if DEBUG
            print("[VisionPoseDetector] Vision error: \(error)")
            #endif
            let result = edgeCaseHandler.evaluate(nil, allPoses: [])
            deliverResult(result.selectedPose, warnings: result.warnings)
        }
    }

    /// Resets the edge-case handler state. Call when starting a new workout session.
    func reset() {
        edgeCaseHandler.reset()
    }

    // MARK: - Private Helpers

    /// Converts a `VNHumanBodyPoseObservation` into a `BodyPose`.
    private func buildPose(
        from observation: VNHumanBodyPoseObservation,
        timestamp: Double
    ) -> BodyPose {
        var joints: [JointName: Joint] = [:]
        joints.reserveCapacity(JointName.allCases.count)

        for jointName in JointName.allCases {
            guard let point = try? observation.recognizedPoint(jointName.vnJointName) else {
                // Joint not present in this observation -- insert a zero-confidence
                // placeholder so downstream code can always subscript safely.
                joints[jointName] = Joint(
                    name: jointName,
                    position: .zero,
                    confidence: 0
                )
                continue
            }

            joints[jointName] = Joint(
                name: jointName,
                // Vision returns normalised coordinates with origin at bottom-left.
                // We preserve this convention; callers convert as needed.
                position: CGPoint(x: point.x, y: point.y),
                confidence: point.confidence
            )
        }

        return BodyPose(joints: joints, timestamp: timestamp)
    }

    /// Delivers the result to both the delegate and the `@Published` properties.
    private func deliverResult(_ pose: BodyPose?, warnings: [EdgeCaseWarning]) {
        // Capture a strong reference to the delegate for the duration of the
        // call. The lock-protected getter returns a strong optional; holding
        // it here prevents deallocation between the nil-check and the call.
        let currentDelegate = delegate
        currentDelegate?.poseDetector(self, didDetect: pose, warnings: warnings)

        DispatchQueue.main.async { [weak self] in
            self?.currentPose = pose
            self?.activeWarnings = warnings
        }
    }
}

// MARK: - VisionPoseDetector + CameraManagerDelegate

/// Convenience conformance so `VisionPoseDetector` can be set directly as the
/// `CameraManager.delegate` without an intermediate adapter.
extension VisionPoseDetector: CameraManagerDelegate {

    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        process(sampleBuffer, cameraPosition: manager.currentPosition)
    }
}
