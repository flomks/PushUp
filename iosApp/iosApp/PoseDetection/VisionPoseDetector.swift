import AVFoundation
import Combine
import CoreMedia
import Vision

// MARK: - PoseDetectorDelegate

/// Receives pose detection results on the detector's internal serial queue.
///
/// Implementations must be non-blocking. Dispatch UI updates to the main queue.
protocol PoseDetectorDelegate: AnyObject {
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
final class VisionPoseDetector: ObservableObject {

    // MARK: - Published State

    /// The most recently detected pose, updated on the main queue.
    /// `nil` when no person is visible or detection is paused.
    @Published private(set) var currentPose: BodyPose?

    // MARK: - Delegate

    weak var delegate: PoseDetectorDelegate?

    // MARK: - Configuration

    /// When `true`, the detector processes every incoming frame.
    /// Set to `false` to pause detection without stopping the camera.
    var isEnabled: Bool = true

    // MARK: - Private State

    /// Reusable request — creating it once avoids per-frame allocation overhead.
    private let bodyPoseRequest = VNDetectHumanBodyPoseRequest()

    /// Guards against re-entrant processing when a frame arrives before the
    /// previous Vision request has completed.
    private var isProcessing: Bool = false

    /// Monotonically increasing frame counter used for debug logging.
    private var frameCount: UInt64 = 0

    // MARK: - Init

    init() {
        // Limit to one observation (the most prominent person in the frame).
        // Setting maximumObservationCount = 1 avoids allocating results for
        // multiple people and keeps latency minimal.
        bodyPoseRequest.maximumObservationCount = 1
    }

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
        guard isEnabled, !isProcessing else { return }
        isProcessing = true
        frameCount &+= 1

        defer { isProcessing = false }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // Obtain the pixel buffer. Vision can also accept CVPixelBuffer directly.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            deliverResult(nil)
            return
        }

        // Build a handler for this frame. Using `.image` orientation ensures
        // Vision interprets the buffer in the correct upright orientation
        // (the camera output is already rotated to portrait by CameraManager).
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )

        do {
            #if DEBUG
            let start = CACurrentMediaTime()
            #endif

            try handler.perform([bodyPoseRequest])

            #if DEBUG
            let elapsed = (CACurrentMediaTime() - start) * 1_000
            if frameCount % 30 == 0 {
                // Log every 30 frames (~1 s at 30 FPS) to avoid log spam.
                print("[VisionPoseDetector] frame \(frameCount): \(String(format: "%.1f", elapsed)) ms")
            }
            #endif

            let pose = buildPose(from: bodyPoseRequest.results?.first, timestamp: timestamp)
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
                // Joint not present in this observation — insert a zero-confidence placeholder
                // so downstream code can always subscript without optional chaining.
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
        delegate?.poseDetector(self, didDetect: pose)
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
