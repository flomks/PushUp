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
    func poseDetector(_ detector: VisionPoseDetector, didDetect pose: BodyPose?)
}

// MARK: - VisionPoseDetector

/// Processes `CMSampleBuffer` video frames using `VNDetectHumanBodyPoseRequest`
/// and publishes `BodyPose` snapshots at up to 30 FPS.
///
/// **Threading model**
/// - `process(_:)` is designed to be called from `CameraManager`'s
///   `videoOutputQueue` (`.userInteractive` QoS).
/// - All Vision work runs synchronously on the calling queue so that the
///   result is available within the same frame budget.
/// - `delegate` callbacks are delivered on the same queue as `process(_:)`.
/// - The `@Published` `currentPose` property is always updated on the **main queue**.
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

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Submits `sampleBuffer` to Vision for body pose detection.
    ///
    /// This method is **synchronous** and should be called from a background
    /// queue (e.g. `CameraManager`'s `videoOutputQueue`). It returns quickly
    /// when `isEnabled == false` or when a previous frame is still being
    /// processed.
    ///
    /// - Parameter sampleBuffer: A video frame delivered by `AVCaptureOutput`.
    func process(_ sampleBuffer: CMSampleBuffer) {
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
            deliverResult(nil)
            return
        }

        // Build a handler for this frame. The `.up` orientation ensures
        // Vision interprets the buffer in the correct upright orientation
        // (the camera output is already rotated to portrait by CameraManager).
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
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

            let pose = buildPose(from: request.results?.first, timestamp: timestamp)
            deliverResult(pose)

        } catch {
            #if DEBUG
            print("[VisionPoseDetector] Vision error: \(error)")
            #endif
            deliverResult(nil)
        }
    }

    // MARK: - Private Helpers

    /// Converts a `VNHumanBodyPoseObservation` into a `BodyPose`.
    ///
    /// Returns `nil` when `observation` is `nil` (no person detected).
    private func buildPose(
        from observation: VNHumanBodyPoseObservation?,
        timestamp: Double
    ) -> BodyPose? {
        guard let observation else { return nil }

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

    /// Delivers the result to both the delegate and the `@Published` property.
    private func deliverResult(_ pose: BodyPose?) {
        // Capture a strong reference to the delegate for the duration of the
        // call. The lock-protected getter returns a strong optional; holding
        // it here prevents deallocation between the nil-check and the call.
        let currentDelegate = delegate
        currentDelegate?.poseDetector(self, didDetect: pose)

        DispatchQueue.main.async { [weak self] in
            self?.currentPose = pose
        }
    }
}

// MARK: - VisionPoseDetector + CameraManagerDelegate

/// Convenience conformance so `VisionPoseDetector` can be set directly as the
/// `CameraManager.delegate` without an intermediate adapter.
extension VisionPoseDetector: CameraManagerDelegate {

    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        process(sampleBuffer)
    }
}
