import CoreGraphics
import Foundation

// MARK: - PushUpEvent

/// Payload delivered to `PushUpDetectorDelegate` when a push-up is counted.
struct PushUpEvent: Sendable {

    /// The total number of push-ups counted in the current session (including
    /// this one).
    let count: Int

    /// The averaged elbow angle (degrees) at the moment the push-up was counted.
    /// Useful for downstream quality scoring (Task 2.4).
    let elbowAngleAtCompletion: Double

    /// The timestamp of the frame that triggered the count, in seconds since
    /// device boot (from `BodyPose.timestamp`).
    let timestamp: Double
}

// MARK: - PushUpDetectorDelegate

/// Receives push-up detection events on the video output queue.
///
/// Implementations must be non-blocking. Dispatch UI updates to the main queue.
protocol PushUpDetectorDelegate: AnyObject, Sendable {

    /// Called exactly once per counted push-up, on the video output queue.
    /// - Parameters:
    ///   - detector: The detector that produced the event.
    ///   - event: Details about the push-up that was counted.
    func pushUpDetector(_ detector: PushUpDetector, didCount event: PushUpEvent)
}

// MARK: - PushUpDetector

/// Analyses a stream of `BodyPose` frames and counts complete push-up cycles.
///
/// **Algorithm overview**
/// 1. For each frame, compute the elbow angle on both sides using the
///    shoulder-elbow-wrist joint triple.
/// 2. Average the left and right angles (or use whichever side has higher
///    confidence when only one side is visible).
/// 3. Feed the averaged angle into a `PushUpStateMachine` that applies
///    hysteresis and cooldown to produce a robust count.
///
/// **Elbow angle calculation**
/// The angle at joint B in the triple (A, B, C) is computed as the angle
/// between vectors BA and BC using the dot-product formula:
/// ```
/// angle = acos( (BA . BC) / (|BA| * |BC|) )
/// ```
/// All arithmetic is performed in `Double` precision. Vision coordinates
/// (origin bottom-left, y increases upward) are used directly; the formula
/// is invariant to coordinate-system orientation.
///
/// **Side selection**
/// - If both sides are detected: use the average of left and right angles.
/// - If only one side is detected: use that side's angle.
/// - If neither side is detected: pass `nil` to the state machine (no-op).
///
/// **Thread safety**
/// `PushUpDetector` is designed to be called from a single serial queue
/// (typically `CameraManager`'s `videoOutputQueue`). The `delegate` property
/// is protected by an `NSLock` so it can be safely set from the main queue
/// and read from the video output queue.
///
/// **Usage**
/// ```swift
/// let detector = PushUpDetector()
/// detector.delegate = self
///
/// // Inside PoseDetectorDelegate:
/// func poseDetector(_ detector: VisionPoseDetector, didDetect pose: BodyPose?) {
///     pushUpDetector.process(pose)
/// }
/// ```
final class PushUpDetector {

    // MARK: - Delegate (thread-safe)

    /// Protected by `delegateLock` so it can be set from the main queue and
    /// read safely from the video output queue inside `process(_:)`.
    private let delegateLock = NSLock()
    private weak var _delegate: PushUpDetectorDelegate?

    var delegate: PushUpDetectorDelegate? {
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

    // MARK: - Public State

    /// Total push-ups counted in the current session.
    var pushUpCount: Int { stateMachine.pushUpCount }

    /// The current phase of the push-up cycle.
    var currentPhase: PushUpPhase { stateMachine.phase }

    /// The most recently computed averaged elbow angle, or `nil` when the pose
    /// was not detected. Useful for real-time UI feedback (e.g. an angle gauge).
    private(set) var currentElbowAngle: Double?

    // MARK: - Private

    private let stateMachine: PushUpStateMachine

    // MARK: - Init

    /// Creates a detector with the given state machine configuration.
    /// - Parameter configuration: Thresholds and hysteresis settings.
    ///   Defaults to `PushUpStateMachine.Configuration.default`.
    init(configuration: PushUpStateMachine.Configuration = .default) {
        self.stateMachine = PushUpStateMachine(configuration: configuration)
    }

    // MARK: - Public API

    /// Processes a single `BodyPose` frame.
    ///
    /// - Parameter pose: The pose for the current frame, or `nil` when no
    ///   person was detected. A `nil` pose advances the cooldown timer but
    ///   does not advance any pending-transition counter.
    func process(_ pose: BodyPose?) {
        let angle = Self.computeElbowAngle(from: pose)
        currentElbowAngle = angle

        let counted = stateMachine.update(angle: angle)

        if counted {
            // Safe unwrap: `stateMachine.update` only returns `true` from
            // `handleDown`, which requires a non-nil, finite angle via its
            // `guard let angle` statement. If this invariant is ever broken
            // by a future refactor, the assertionFailure will fire in debug
            // builds and the fallback prevents a production crash.
            guard let completionAngle = angle, let pose else {
                assertionFailure(
                    "angle and pose must be non-nil when a push-up is counted"
                )
                return
            }
            let event = PushUpEvent(
                count: stateMachine.pushUpCount,
                elbowAngleAtCompletion: completionAngle,
                timestamp: pose.timestamp
            )
            // Capture a strong reference to the delegate for the duration of
            // the call. The lock-protected getter returns a strong optional.
            let currentDelegate = delegate
            currentDelegate?.pushUpDetector(self, didCount: event)
        }
    }

    /// Resets the detector and its underlying state machine.
    /// Call this when starting a new workout session.
    func reset() {
        stateMachine.reset()
        currentElbowAngle = nil
    }

    // MARK: - Angle Computation

    /// Returns the averaged elbow angle (degrees) from the pose, or `nil` when
    /// no usable joints are available.
    static func computeElbowAngle(from pose: BodyPose?) -> Double? {
        guard let pose else { return nil }

        let leftAngle  = elbowAngle(
            shoulder: pose.leftShoulder,
            elbow:    pose.leftElbow,
            wrist:    pose.leftWrist
        )
        let rightAngle = elbowAngle(
            shoulder: pose.rightShoulder,
            elbow:    pose.rightElbow,
            wrist:    pose.rightWrist
        )

        switch (leftAngle, rightAngle) {
        case let (l?, r?):   return (l + r) / 2.0
        case let (l?, nil):  return l
        case let (nil, r?):  return r
        case (nil, nil):     return nil
        }
    }

    /// Computes the angle at `elbow` formed by the vectors elbow->shoulder and
    /// elbow->wrist, in degrees.
    ///
    /// Returns `nil` when any of the three joints is missing or below the
    /// confidence threshold.
    static func elbowAngle(
        shoulder: Joint?,
        elbow: Joint?,
        wrist: Joint?
    ) -> Double? {
        guard
            let shoulder, shoulder.isDetected,
            let elbow,    elbow.isDetected,
            let wrist,    wrist.isDetected
        else { return nil }

        return angleBetween(
            a: shoulder.position,
            vertex: elbow.position,
            b: wrist.position
        )
    }

    // MARK: - Geometry

    /// Returns the angle at `vertex` formed by the vectors vertex->a and
    /// vertex->b, in degrees.
    ///
    /// All arithmetic is performed in `Double` to avoid precision loss on
    /// platforms where `CGFloat` is 32-bit.
    ///
    /// Uses the dot-product formula:
    /// ```
    /// angle = acos( (va . vb) / (|va| * |vb|) )
    /// ```
    /// Returns `nil` when either vector has zero length (degenerate case where
    /// two joints share the same position).
    static func angleBetween(a: CGPoint, vertex: CGPoint, b: CGPoint) -> Double? {
        // Promote to Double immediately to ensure full precision on all platforms.
        let vax = Double(a.x - vertex.x)
        let vay = Double(a.y - vertex.y)
        let vbx = Double(b.x - vertex.x)
        let vby = Double(b.y - vertex.y)

        let magA = (vax * vax + vay * vay).squareRoot()
        let magB = (vbx * vbx + vby * vby).squareRoot()

        guard magA > 0, magB > 0 else { return nil }

        let dot = vax * vbx + vay * vby
        // Clamp to [-1, 1] to guard against floating-point rounding errors
        // that would cause acos to return NaN.
        let cosAngle = max(-1.0, min(1.0, dot / (magA * magB)))
        return acos(cosAngle) * (180.0 / .pi)
    }
}
