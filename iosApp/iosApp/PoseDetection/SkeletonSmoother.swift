import CoreGraphics

// MARK: - SkeletonSmoother

/// Applies Exponential Moving Average (EMA) smoothing to joint positions
/// to reduce frame-to-frame jitter in the skeleton overlay.
///
/// **Important**: Only use smoothed positions for **rendering**. The raw
/// (unsmoothed) positions must be used for angle calculations and the state
/// machine to avoid introducing lag into the push-up counting logic.
///
/// **EMA formula**:
/// ```
/// smoothed = alpha * raw + (1 - alpha) * previous_smoothed
/// ```
///
/// **Reset logic**: When a joint disappears for `resetFrameThreshold` or more
/// consecutive frames and then reappears, the EMA state is reset to the new
/// raw value instead of slowly gliding from the stale position. This prevents
/// visible "teleport" artefacts.
///
/// **Thread safety**: Not thread-safe. All calls must come from the same
/// serial queue (typically the video output queue).
final class SkeletonSmoother {

    // MARK: - Configuration

    /// Smoothing factor. Higher = more reactive (less smooth), lower = smoother
    /// (more lag). 0.35 provides ~3-frame smoothing at 30 FPS with minimal
    /// perceptible lag.
    let alpha: Double

    /// Number of consecutive frames a joint must be missing before its EMA
    /// state is reset on reappearance.
    let resetFrameThreshold: Int

    // MARK: - State

    /// Per-joint smoothed positions in CGFloat precision.
    private var smoothed: [JointName: CGPoint] = [:]

    /// Per-joint counter of consecutive frames the joint has been missing.
    private var missingCount: [JointName: Int] = [:]

    // MARK: - Init

    init(alpha: Double = 0.35, resetFrameThreshold: Int = 6) {
        self.alpha = alpha
        self.resetFrameThreshold = resetFrameThreshold
    }

    // MARK: - Public API

    /// Returns a new `BodyPose` with smoothed joint positions.
    ///
    /// The returned pose has the same timestamp and confidence values as the
    /// input; only the `position` of each joint is modified.
    ///
    /// Pass `nil` to tick the missing-counters without producing output.
    func smooth(_ pose: BodyPose?) -> BodyPose? {
        guard let pose else {
            // Tick all missing counters
            for name in JointName.allCases {
                missingCount[name, default: 0] += 1
            }
            return nil
        }

        var smoothedJoints: [JointName: Joint] = [:]

        for (name, joint) in pose.joints {
            if !joint.isDetected {
                missingCount[name, default: 0] += 1
                // Keep the stale smoothed position for a few frames so the
                // skeleton does not flicker when a joint briefly drops out.
                if let stale = smoothed[name],
                   (missingCount[name] ?? 0) <= resetFrameThreshold {
                    smoothedJoints[name] = Joint(
                        name: name,
                        position: stale,
                        confidence: joint.confidence
                    )
                } else {
                    smoothed.removeValue(forKey: name)
                    smoothedJoints[name] = joint
                }
                continue
            }

            let wasMissing = missingCount[name] ?? 0
            missingCount[name] = 0

            let raw = joint.position

            if let prev = smoothed[name], wasMissing < resetFrameThreshold {
                // EMA
                let a = CGFloat(alpha)
                let newX = a * raw.x + (1 - a) * prev.x
                let newY = a * raw.y + (1 - a) * prev.y
                let newPos = CGPoint(x: newX, y: newY)
                smoothed[name] = newPos
                smoothedJoints[name] = Joint(
                    name: name,
                    position: newPos,
                    confidence: joint.confidence
                )
            } else {
                // First appearance or after long absence: snap to raw
                smoothed[name] = raw
                smoothedJoints[name] = joint
            }
        }

        return BodyPose(joints: smoothedJoints, timestamp: pose.timestamp)
    }

    /// Resets all smoothing state. Call when starting a new workout session.
    func reset() {
        smoothed.removeAll()
        missingCount.removeAll()
    }
}
