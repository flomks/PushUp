import CoreGraphics
import Foundation

// MARK: - EdgeCaseWarning

/// User-facing warnings produced by `EdgeCaseHandler` when the pose detection
/// environment is suboptimal.
///
/// Warnings are ordered by severity (highest first) so that the UI can display
/// the most actionable hint when multiple conditions are active simultaneously.
enum EdgeCaseWarning: Equatable, Sendable, CustomStringConvertible {

    /// No person was detected in the current frame.
    case noPersonDetected

    /// The detected pose has too few high-confidence joints for reliable
    /// push-up detection (e.g. bad camera angle or partial occlusion).
    case poorAngle

    /// The overall joint confidence is low, which often indicates difficult
    /// lighting conditions (too dark, too bright, or strong backlight).
    case poorLighting

    /// Multiple persons were detected; the handler is tracking the largest one.
    case multiplePersonsDetected

    // MARK: - User-Facing Messages

    /// A short, actionable message suitable for display in the workout UI.
    var userMessage: String {
        switch self {
        case .noPersonDetected:
            return "Bitte positioniere dich im Kamerabild"
        case .poorAngle:
            return "Bitte Handy weiter weg stellen"
        case .poorLighting:
            return "Bessere Beleuchtung fuer genauere Erkennung"
        case .multiplePersonsDetected:
            return "Mehrere Personen erkannt – groesste wird getrackt"
        }
    }

    var description: String { userMessage }
}

// MARK: - EdgeCaseResult

/// The output of a single `EdgeCaseHandler.evaluate(_:allPoses:)` call.
struct EdgeCaseResult: Sendable {

    /// The pose selected for push-up detection, or `nil` when no usable pose
    /// was found (e.g. no person in frame).
    let selectedPose: BodyPose?

    /// Active warnings for the current frame. Empty when conditions are good.
    /// Ordered by severity (most actionable first).
    let warnings: [EdgeCaseWarning]

    /// `true` when `selectedPose` is non-nil and no critical warnings are active.
    var isReliable: Bool {
        selectedPose != nil && !warnings.contains(.noPersonDetected)
    }
}

// MARK: - EdgeCaseHandler

/// Analyses each frame's pose detection output and applies edge-case logic:
///
/// 1. **No person detected** – returns a `noPersonDetected` warning.
/// 2. **Multiple persons** – selects the "largest" (most joints detected /
///    highest bounding-box area) and emits a `multiplePersonsDetected` warning.
/// 3. **Poor angle** – detects when critical push-up joints are missing or
///    have low confidence and emits a `poorAngle` warning.
/// 4. **Poor lighting** – detects when the average joint confidence across
///    all detected joints is below a threshold and emits a `poorLighting` warning.
///
/// **Thread safety**
/// `EdgeCaseHandler` is **not** thread-safe. All calls must come from the same
/// serial queue (typically the video output queue, same as `VisionPoseDetector`).
///
/// **Usage**
/// ```swift
/// let handler = EdgeCaseHandler()
///
/// // Inside VisionPoseDetector after building poses from all observations:
/// let result = handler.evaluate(primaryPose, allPoses: allPoses)
/// // Use result.selectedPose for push-up detection.
/// // Publish result.warnings to the UI.
/// ```
final class EdgeCaseHandler {

    // MARK: - Configuration

    /// Tunable thresholds for edge-case detection.
    struct Configuration: Sendable {

        /// Minimum fraction of required push-up joints that must be detected
        /// (confidence >= `Joint.minimumConfidence`) before a `poorAngle`
        /// warning is suppressed.
        ///
        /// Default: 0.67 (4 of 6 required joints). Lowering this makes the
        /// detector more tolerant of partial occlusion; raising it makes it
        /// stricter.
        let minimumRequiredJointFraction: Double

        /// Average confidence across ALL detected joints below which a
        /// `poorLighting` warning is emitted.
        ///
        /// Default: 0.45. Vision joint confidence is in [0, 1]; values below
        /// ~0.5 typically indicate difficult lighting.
        let poorLightingConfidenceThreshold: Float

        /// Number of consecutive frames a warning must be active before it is
        /// surfaced to the UI. This prevents flickering warnings on transient
        /// single-frame drops.
        ///
        /// Default: 5 frames (~167 ms at 30 FPS).
        let warningHysteresisFrameCount: Int

        /// Number of consecutive frames a warning must be *absent* before it
        /// is cleared from the UI. Prevents rapid on/off toggling.
        ///
        /// Default: 10 frames (~333 ms at 30 FPS).
        let warningClearanceFrameCount: Int

        init(
            minimumRequiredJointFraction: Double = 0.67,
            poorLightingConfidenceThreshold: Float = 0.45,
            warningHysteresisFrameCount: Int = 5,
            warningClearanceFrameCount: Int = 10
        ) {
            precondition(minimumRequiredJointFraction > 0 && minimumRequiredJointFraction <= 1,
                         "minimumRequiredJointFraction must be in (0, 1]")
            precondition(poorLightingConfidenceThreshold > 0 && poorLightingConfidenceThreshold < 1,
                         "poorLightingConfidenceThreshold must be in (0, 1)")
            precondition(warningHysteresisFrameCount >= 1,
                         "warningHysteresisFrameCount must be >= 1")
            precondition(warningClearanceFrameCount >= 1,
                         "warningClearanceFrameCount must be >= 1")
            self.minimumRequiredJointFraction = minimumRequiredJointFraction
            self.poorLightingConfidenceThreshold = poorLightingConfidenceThreshold
            self.warningHysteresisFrameCount = warningHysteresisFrameCount
            self.warningClearanceFrameCount = warningClearanceFrameCount
        }

        static let `default` = Configuration()
    }

    // MARK: - Private State

    private let configuration: Configuration

    /// Per-warning hysteresis counters.
    /// Positive value: frames the warning has been continuously active.
    /// Negative value: frames the warning has been continuously absent.
    private var hysteresisCounters: [EdgeCaseWarning: Int] = [:]

    /// The set of warnings currently surfaced to the UI (after hysteresis).
    private(set) var activeWarnings: Set<EdgeCaseWarning> = []

    // MARK: - Init

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Evaluates the current frame's pose data and returns an `EdgeCaseResult`.
    ///
    /// - Parameters:
    ///   - primaryPose: The single pose produced by `VisionPoseDetector` for
    ///     the primary (first) observation, or `nil` when no person was found.
    ///   - allPoses: All poses produced from all observations in the frame.
    ///     When Vision returns multiple observations (multiple people), this
    ///     array has more than one element.
    /// - Returns: An `EdgeCaseResult` with the selected pose and active warnings.
    func evaluate(_ primaryPose: BodyPose?, allPoses: [BodyPose]) -> EdgeCaseResult {
        var rawWarnings: Set<EdgeCaseWarning> = []

        // --- Step 1: No person detected ---
        guard !allPoses.isEmpty else {
            rawWarnings.insert(.noPersonDetected)
            let surfaced = updateHysteresis(raw: rawWarnings)
            return EdgeCaseResult(selectedPose: nil, warnings: sortedWarnings(surfaced))
        }

        // --- Step 2: Multiple persons – select the largest ---
        let selectedPose: BodyPose
        if allPoses.count > 1 {
            rawWarnings.insert(.multiplePersonsDetected)
            selectedPose = Self.selectLargestPose(from: allPoses)
        } else {
            selectedPose = allPoses[0]
        }

        // --- Step 3: Poor angle (insufficient joint coverage) ---
        if Self.hasPoorAngle(pose: selectedPose, configuration: configuration) {
            rawWarnings.insert(.poorAngle)
        }

        // --- Step 4: Poor lighting (low average confidence) ---
        if Self.hasPoorLighting(pose: selectedPose, configuration: configuration) {
            rawWarnings.insert(.poorLighting)
        }

        let surfaced = updateHysteresis(raw: rawWarnings)
        return EdgeCaseResult(
            selectedPose: selectedPose,
            warnings: sortedWarnings(surfaced)
        )
    }

    /// Resets all hysteresis state. Call when starting a new workout session.
    func reset() {
        hysteresisCounters.removeAll()
        activeWarnings.removeAll()
    }

    // MARK: - Private: Person Selection

    /// Selects the "largest" pose from a set of candidates.
    ///
    /// "Largest" is defined as the pose with the greatest number of detected
    /// joints. When two poses have the same count, the one with the higher
    /// average confidence wins. This heuristic reliably selects the person
    /// closest to the camera (most joints visible, highest confidence).
    /// Selects the "largest" pose from a non-empty array of candidates.
    ///
    /// - Precondition: `poses` must not be empty. In debug builds this is
    ///   enforced by `assertionFailure`; in release builds the method returns
    ///   the first element as a safe fallback.
    static func selectLargestPose(from poses: [BodyPose]) -> BodyPose {
        guard let best = poses.max(by: { a, b in
            let countA = a.detectedJoints.count
            let countB = b.detectedJoints.count
            if countA != countB { return countA < countB }
            // Tie-break by average confidence.
            return averageConfidence(of: a) < averageConfidence(of: b)
        }) else {
            // `max(by:)` returns nil only when the collection is empty.
            // Callers always guard against empty arrays before calling this
            // method, so this branch should never execute.
            assertionFailure("selectLargestPose called with empty array")
            // Return a minimal placeholder pose to avoid crashing in release.
            let placeholder = Dictionary(
                uniqueKeysWithValues: JointName.allCases.map { name in
                    (name, Joint(name: name, position: .zero, confidence: 0))
                }
            )
            return BodyPose(joints: placeholder, timestamp: 0)
        }
        return best
    }

    // MARK: - Private: Angle Check

    /// Returns `true` when the pose does not have enough high-confidence joints
    /// for reliable push-up detection.
    ///
    /// Checks the six joints required for push-up detection:
    /// shoulders, elbows, and wrists. If fewer than
    /// `configuration.minimumRequiredJointFraction` of them are detected, the
    /// angle is considered poor.
    static func hasPoorAngle(
        pose: BodyPose,
        configuration: Configuration = .default
    ) -> Bool {
        let required: [JointName] = [
            .leftShoulder, .rightShoulder,
            .leftElbow,    .rightElbow,
            .leftWrist,    .rightWrist
        ]
        let detectedCount = required.filter { pose.joints[$0]?.isDetected == true }.count
        let fraction = Double(detectedCount) / Double(required.count)
        return fraction < configuration.minimumRequiredJointFraction
    }

    // MARK: - Private: Lighting Check

    /// Returns `true` when the average confidence of all joints in the pose
    /// is below `configuration.poorLightingConfidenceThreshold`.
    ///
    /// Low average confidence across all joints is a reliable proxy for
    /// difficult lighting: in dark conditions or strong backlight, Vision
    /// returns lower confidence scores for all joints simultaneously.
    static func hasPoorLighting(
        pose: BodyPose,
        configuration: Configuration = .default
    ) -> Bool {
        let avg = averageConfidence(of: pose)
        // Only flag lighting if we have at least some joints to measure.
        guard avg > 0 else { return false }
        return avg < configuration.poorLightingConfidenceThreshold
    }

    // MARK: - Private: Hysteresis

    /// Updates the hysteresis counters for each warning and returns the set of
    /// warnings that should currently be surfaced to the UI.
    ///
    /// A warning is surfaced when its counter reaches `warningHysteresisFrameCount`.
    /// A warning is cleared when its absence counter reaches `warningClearanceFrameCount`.
    /// Pre-computed array of all warning cases to avoid allocating a new array
    /// on every frame in the hot path.
    private static let allWarningCases = EdgeCaseWarning.allCases

    private func updateHysteresis(raw: Set<EdgeCaseWarning>) -> Set<EdgeCaseWarning> {
        let allWarnings = Self.allWarningCases

        for warning in allWarnings {
            let isActive = raw.contains(warning)
            let current = hysteresisCounters[warning, default: 0]

            if isActive {
                // Warning is present this frame: increment positive counter.
                let newCount = max(0, current) + 1
                hysteresisCounters[warning] = newCount
                if newCount >= configuration.warningHysteresisFrameCount {
                    activeWarnings.insert(warning)
                }
            } else {
                // Warning is absent this frame: decrement toward clearance.
                let newCount = min(0, current) - 1
                hysteresisCounters[warning] = newCount
                if abs(newCount) >= configuration.warningClearanceFrameCount {
                    activeWarnings.remove(warning)
                    hysteresisCounters[warning] = 0
                }
            }
        }

        return activeWarnings
    }

    // MARK: - Private: Helpers

    /// Returns the arithmetic mean confidence of all joints with non-zero
    /// confidence in the pose. Returns 0 when no joints have positive confidence.
    ///
    /// Only joints with `confidence > 0` are included in the average. This
    /// excludes placeholder joints that Vision did not attempt to detect,
    /// giving a more accurate signal for lighting quality assessment.
    private static func averageConfidence(of pose: BodyPose) -> Float {
        let detected = pose.joints.values.filter { $0.confidence > 0 }
        guard !detected.isEmpty else { return 0 }
        let total = detected.reduce(Float(0)) { $0 + $1.confidence }
        return total / Float(detected.count)
    }

    /// Returns warnings sorted by severity (most actionable first).
    private func sortedWarnings(_ warnings: Set<EdgeCaseWarning>) -> [EdgeCaseWarning] {
        let order: [EdgeCaseWarning] = [
            .noPersonDetected,
            .poorAngle,
            .poorLighting,
            .multiplePersonsDetected
        ]
        return order.filter { warnings.contains($0) }
    }
}

// MARK: - EdgeCaseWarning + CaseIterable

extension EdgeCaseWarning: CaseIterable {
    static var allCases: [EdgeCaseWarning] {
        [.noPersonDetected, .poorAngle, .poorLighting, .multiplePersonsDetected]
    }
}
