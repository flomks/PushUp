import CoreGraphics
import Foundation

// MARK: - FormScore

/// The quality scores for a single completed push-up.
///
/// Both component scores and the combined score are in the range [0.0, 1.0].
/// These values are intended to be stored in a `PushUpRecord` (depthScore,
/// formScore fields) and used to compute the session quality average.
struct FormScore: Equatable, Sendable {

    // MARK: - Component Scores

    /// Depth quality: how low the person went during the DOWN phase.
    ///
    /// Derived from the minimum elbow angle observed while the state machine
    /// was in the `.down` phase:
    /// - angle >= 90°  → 0.0  (barely bent)
    /// - angle == 90°  → 0.5  (spec anchor point)
    /// - angle == 70°  → 0.8  (spec anchor point)
    /// - angle <= 60°  → 1.0  (full depth)
    ///
    /// The mapping is piecewise-linear between the three anchor points and
    /// clamped to [0, 1] outside the defined range.
    let depthScore: Double

    /// Form quality: how well the body was held during the push-up.
    ///
    /// Composite of up to three sub-scores, averaged over whichever are
    /// available for the current camera angle:
    /// 1. **Back alignment** – shoulder-hip line is horizontal (parallel to
    ///    the ground). Deviations from horizontal reduce this sub-score.
    /// 2. **Arm symmetry** – left and right elbow angles are similar.
    ///    Large asymmetry reduces this sub-score.
    /// 3. **Movement smoothness** – no abrupt jumps in elbow angle between
    ///    consecutive frames. Jerky movement reduces this sub-score.
    let formScore: Double

    // MARK: - Combined Score

    /// The arithmetic mean of `depthScore` and `formScore`.
    ///
    /// This is the value stored in `PushUpRecord.quality` and used by
    /// `FinishWorkoutUseCase` when computing the quality multiplier.
    var combinedScore: Double { (depthScore + formScore) / 2.0 }
}

// MARK: - FormScorer

/// Accumulates body-pose data during a push-up cycle and produces a
/// `FormScore` when the cycle completes.
///
/// **Usage**
/// ```swift
/// let scorer = FormScorer()
///
/// // Inside the pose-processing loop (same queue as PushUpDetector):
/// scorer.recordFrame(
///     pose: currentPose,
///     leftElbowAngle: leftAngle,
///     rightElbowAngle: rightAngle,
///     isInDownPhase: stateMachine.phase == .down
/// )
///
/// // When PushUpDetector fires a push-up event:
/// if let score = scorer.finalisePushUp() {
///     // store score.depthScore and score.formScore in PushUpRecord
/// }
/// ```
///
/// **Thread safety**
/// `FormScorer` is **not** thread-safe. All calls must come from the same
/// serial queue (typically the video output queue, same as `PushUpDetector`).
final class FormScorer {

    // MARK: - Configuration

    /// Tunable parameters for the scoring algorithm.
    struct Configuration: Sendable {

        // MARK: Depth scoring anchors

        /// Elbow angle (degrees) that maps to a depth score of 0.5.
        /// Default: 90° (spec anchor). Must be greater than `depthAnchorHigh`.
        let depthAnchorHalf: Double

        /// Elbow angle (degrees) that maps to a depth score of 0.8.
        /// Default: 70° (spec anchor). Must be greater than `depthAnchorFull`.
        let depthAnchorHigh: Double

        /// Elbow angle (degrees) at or below which the depth score is 1.0.
        /// Default: 60° (spec anchor). Must be positive.
        let depthAnchorFull: Double

        // MARK: Form scoring thresholds

        /// Maximum shoulder-hip angle deviation (degrees) from horizontal
        /// before the back-alignment sub-score reaches 0.
        /// Default: 30°. Must be positive.
        let maxBackAngleDeviation: Double

        /// Maximum left-right elbow angle difference (degrees) before the
        /// arm-symmetry sub-score reaches 0.
        /// Default: 30°. Must be positive.
        let maxArmAsymmetry: Double

        /// Maximum frame-to-frame elbow angle change (degrees) before the
        /// smoothness sub-score for that frame reaches 0.
        /// Default: 30°. Must be positive.
        let maxFrameAngleDelta: Double

        // MARK: Init

        init(
            depthAnchorHalf: Double = 90.0,
            depthAnchorHigh: Double = 70.0,
            depthAnchorFull: Double = 60.0,
            maxBackAngleDeviation: Double = 30.0,
            maxArmAsymmetry: Double = 30.0,
            maxFrameAngleDelta: Double = 30.0
        ) {
            precondition(
                depthAnchorFull > 0 && depthAnchorFull < depthAnchorHigh && depthAnchorHigh < depthAnchorHalf,
                "Depth anchors must satisfy 0 < full(\(depthAnchorFull)) < high(\(depthAnchorHigh)) < half(\(depthAnchorHalf))"
            )
            precondition(maxBackAngleDeviation > 0,
                         "maxBackAngleDeviation must be positive, got \(maxBackAngleDeviation)")
            precondition(maxArmAsymmetry > 0,
                         "maxArmAsymmetry must be positive, got \(maxArmAsymmetry)")
            precondition(maxFrameAngleDelta > 0,
                         "maxFrameAngleDelta must be positive, got \(maxFrameAngleDelta)")
            self.depthAnchorHalf      = depthAnchorHalf
            self.depthAnchorHigh      = depthAnchorHigh
            self.depthAnchorFull      = depthAnchorFull
            self.maxBackAngleDeviation = maxBackAngleDeviation
            self.maxArmAsymmetry      = maxArmAsymmetry
            self.maxFrameAngleDelta   = maxFrameAngleDelta
        }

        /// Default configuration matching the Task 2.4 specification.
        static let `default` = Configuration()
    }

    // MARK: - Private State

    private let configuration: Configuration

    /// Minimum averaged elbow angle observed while in the DOWN phase.
    /// Initialised to `.infinity` so any real angle is smaller.
    /// Reset at the start of each push-up cycle via `reset()`.
    private var minDownPhaseAngle: Double = .infinity

    /// Accumulated back-alignment sub-scores across all frames in the current
    /// push-up cycle where hip joints were detected.
    private var backAlignmentSamples: [Double] = []

    /// Accumulated arm-symmetry sub-scores across all frames in the current
    /// push-up cycle where both arms were detected.
    private var armSymmetrySamples: [Double] = []

    /// Accumulated smoothness sub-scores across all frames in the current
    /// push-up cycle where consecutive angle data was available.
    private var smoothnessSamples: [Double] = []

    /// The averaged elbow angle from the previous frame, used to compute the
    /// frame-to-frame delta for the smoothness sub-score.
    private var previousAveragedAngle: Double?

    // MARK: - Init

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Records a single video frame during an active push-up cycle.
    ///
    /// Call this for every frame while the push-up state machine is active
    /// (i.e. between the moment the DOWN threshold is first crossed and the
    /// moment the push-up is counted).
    ///
    /// - Parameters:
    ///   - pose: The body pose for this frame, or `nil` when no person is
    ///     detected. A nil pose skips all sub-score sampling and resets the
    ///     smoothness baseline so the next valid frame does not produce a
    ///     spurious large delta.
    ///   - leftElbowAngle: The left-arm elbow angle in degrees, or `nil` when
    ///     the left arm joints are not detected or below confidence threshold.
    ///   - rightElbowAngle: The right-arm elbow angle in degrees, or `nil`
    ///     when the right arm joints are not detected or below confidence threshold.
    ///   - isInDownPhase: `true` while the state machine is in `.down`.
    ///     Only frames in the DOWN phase contribute to `depthScore`.
    func recordFrame(
        pose: BodyPose?,
        leftElbowAngle: Double?,
        rightElbowAngle: Double?,
        isInDownPhase: Bool
    ) {
        let averaged = Self.averagedAngle(left: leftElbowAngle, right: rightElbowAngle)

        // --- Depth tracking (DOWN phase only) ---
        if isInDownPhase, let angle = averaged, angle.isFinite {
            minDownPhaseAngle = min(minDownPhaseAngle, angle)
        }

        // --- Form sub-scores (all frames) ---

        // Back alignment: requires at least one shoulder and one hip joint.
        if let pose, let score = Self.backAlignmentScore(pose: pose, configuration: configuration) {
            backAlignmentSamples.append(score)
        }

        // Arm symmetry: requires both arms to be detected.
        if let left = leftElbowAngle, let right = rightElbowAngle,
           left.isFinite, right.isFinite {
            let asymmetry = abs(left - right)
            let score = max(0.0, 1.0 - asymmetry / configuration.maxArmAsymmetry)
            armSymmetrySamples.append(score)
        }

        // Smoothness: frame-to-frame angle delta.
        if let current = averaged, current.isFinite {
            if let previous = previousAveragedAngle {
                let delta = abs(current - previous)
                let score = max(0.0, 1.0 - delta / configuration.maxFrameAngleDelta)
                smoothnessSamples.append(score)
            }
            previousAveragedAngle = current
        } else {
            // Missing pose: reset the baseline so the next valid frame does
            // not produce a spurious large delta.
            previousAveragedAngle = nil
        }
    }

    /// Finalises the current push-up cycle and returns the computed scores.
    ///
    /// After calling this method the scorer is automatically reset and ready
    /// to accumulate data for the next push-up.
    ///
    /// - Returns: A `FormScore` for the completed push-up, or `nil` when
    ///   insufficient data was collected (no DOWN-phase angle data and no
    ///   form sub-score samples at all).
    @discardableResult
    func finalisePushUp() -> FormScore? {
        defer { reset() }
        let depth = computeDepthScore()
        let form  = computeFormScore()
        guard let depth, let form else { return nil }
        return FormScore(depthScore: depth, formScore: form)
    }

    /// Resets all accumulated state without producing a score.
    ///
    /// Call this when a workout session is cancelled or the detector is reset.
    func reset() {
        minDownPhaseAngle = .infinity
        backAlignmentSamples.removeAll(keepingCapacity: true)
        armSymmetrySamples.removeAll(keepingCapacity: true)
        smoothnessSamples.removeAll(keepingCapacity: true)
        previousAveragedAngle = nil
    }

    // MARK: - Depth Score

    /// Computes the depth score from the minimum elbow angle observed during
    /// the DOWN phase using piecewise-linear interpolation between the three
    /// spec anchor points.
    ///
    /// Returns `nil` when no DOWN-phase angle data was collected.
    func computeDepthScore() -> Double? {
        guard minDownPhaseAngle.isFinite else { return nil }
        return Self.depthScore(for: minDownPhaseAngle, configuration: configuration)
    }

    /// Maps an elbow angle to a depth score using piecewise-linear
    /// interpolation between the three spec anchor points.
    ///
    /// Anchor mapping (from spec):
    /// - angle >= 90° → 0.0  (no depth credit above the DOWN threshold)
    /// - angle == 90° → 0.5
    /// - angle == 70° → 0.8
    /// - angle <= 60° → 1.0
    ///
    /// Exposed as a `static` pure function for unit testing.
    static func depthScore(
        for angle: Double,
        configuration: Configuration = .default
    ) -> Double {
        let half = configuration.depthAnchorHalf  // 90° → 0.5
        let high = configuration.depthAnchorHigh  // 70° → 0.8
        let full = configuration.depthAnchorFull  // 60° → 1.0

        if angle >= half {
            return 0.0
        } else if angle >= high {
            // Segment [high, half]: score rises from 0.5 to 0.8 as angle falls.
            let t = (half - angle) / (half - high)
            return 0.5 + t * 0.3
        } else if angle >= full {
            // Segment [full, high]: score rises from 0.8 to 1.0 as angle falls.
            let t = (high - angle) / (high - full)
            return 0.8 + t * 0.2
        } else {
            return 1.0
        }
    }

    // MARK: - Form Score

    /// Computes the composite form score as the mean of whichever sub-score
    /// averages have at least one sample.
    ///
    /// This is intentionally lenient: if hip joints were never detected (e.g.
    /// the camera angle only shows the upper body) the back-alignment
    /// sub-score is simply omitted and the remaining sub-scores are averaged.
    ///
    /// Returns `nil` only when no sub-score samples were collected at all.
    func computeFormScore() -> Double? {
        let candidates: [Double?] = [
            backAlignmentSamples.isEmpty  ? nil : backAlignmentSamples.mean,
            armSymmetrySamples.isEmpty    ? nil : armSymmetrySamples.mean,
            smoothnessSamples.isEmpty     ? nil : smoothnessSamples.mean,
        ]
        let available = candidates.compactMap { $0 }
        guard !available.isEmpty else { return nil }
        return available.reduce(0, +) / Double(available.count)
    }

    // MARK: - Back Alignment Sub-Score

    /// Maps a body pose to a back-alignment score in [0, 1].
    ///
    /// The score is based on the angle of the shoulder-midpoint to
    /// hip-midpoint line relative to horizontal. A perfectly horizontal spine
    /// (parallel to the ground in push-up position) scores 1.0. Deviations
    /// reduce the score linearly to 0 at `maxBackAngleDeviation`.
    ///
    /// Returns `nil` when neither shoulder nor hip can be located (both joints
    /// on both sides are below the confidence threshold).
    ///
    /// Exposed as a `static` pure function for unit testing.
    static func backAlignmentScore(
        pose: BodyPose,
        configuration: Configuration = .default
    ) -> Double? {
        guard
            let shoulder = midpoint(a: pose.leftShoulder, b: pose.rightShoulder),
            let hip      = midpoint(a: pose.leftHip,      b: pose.rightHip)
        else { return nil }

        let dx = Double(hip.x - shoulder.x)
        let dy = Double(hip.y - shoulder.y)

        // Degenerate case: shoulder and hip at the same position.
        guard dx != 0 || dy != 0 else { return 1.0 }

        let angleFromHorizontal = abs(atan2(dy, dx) * (180.0 / .pi))
        return max(0.0, 1.0 - angleFromHorizontal / configuration.maxBackAngleDeviation)
    }

    // MARK: - Geometry Helpers

    /// Returns the midpoint of two detected joints, the position of whichever
    /// single joint is detected, or `nil` when neither is detected.
    private static func midpoint(a: Joint?, b: Joint?) -> CGPoint? {
        let detectedA = a?.isDetected == true ? a : nil
        let detectedB = b?.isDetected == true ? b : nil
        switch (detectedA, detectedB) {
        case let (a?, b?):
            return CGPoint(
                x: (a.position.x + b.position.x) / 2,
                y: (a.position.y + b.position.y) / 2
            )
        case let (a?, nil): return a.position
        case let (nil, b?): return b.position
        case (nil, nil):    return nil
        }
    }

    /// Returns the average of two optional angles, or whichever is non-nil,
    /// or `nil` when both are nil.
    static func averagedAngle(left: Double?, right: Double?) -> Double? {
        switch (left, right) {
        case let (l?, r?):  return (l + r) / 2.0
        case let (l?, nil): return l
        case let (nil, r?): return r
        case (nil, nil):    return nil
        }
    }
}

// MARK: - Array + mean (internal)

extension Array where Element == Double {
    /// The arithmetic mean of the array's elements.
    /// Callers are responsible for ensuring the array is non-empty before calling.
    var mean: Double {
        precondition(!isEmpty, "mean called on empty array")
        return reduce(0, +) / Double(count)
    }
}
