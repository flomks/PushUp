import CoreGraphics
import Vision

// MARK: - JointName

/// The set of body joints extracted per frame.
///
/// Covers all joints required for push-up detection (shoulders, elbows,
/// wrists, hips) plus knees for future exercise support.
enum JointName: String, CaseIterable, Hashable {
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee

    /// The corresponding `VNHumanBodyPoseObservation.JointName` used when
    /// querying Vision results.
    var vnJointName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .leftShoulder:  return .leftShoulder
        case .rightShoulder: return .rightShoulder
        case .leftElbow:     return .leftElbow
        case .rightElbow:    return .rightElbow
        case .leftWrist:     return .leftWrist
        case .rightWrist:    return .rightWrist
        case .leftHip:       return .leftHip
        case .rightHip:      return .rightHip
        case .leftKnee:      return .leftKnee
        case .rightKnee:     return .rightKnee
        }
    }
}

// MARK: - Joint

/// A single body joint with a normalised position and a confidence score.
///
/// - `position`: Normalised coordinates in the range [0, 1] where (0, 0) is
///   the bottom-left of the image and (1, 1) is the top-right, matching the
///   Vision framework's coordinate system.
/// - `confidence`: Value in [0, 1] reported by Vision. Joints below the
///   `BodyPose.minimumConfidence` threshold are marked `isDetected = false`.
struct Joint: Equatable {

    /// Minimum confidence threshold below which a joint is considered undetected.
    static let minimumConfidence: Float = 0.3

    let name: JointName

    /// Normalised position (Vision coordinate space: origin bottom-left).
    let position: CGPoint

    /// Confidence score in [0, 1] as reported by `VNRecognizedPoint`.
    let confidence: Float

    /// `true` when `confidence >= Joint.minimumConfidence`.
    var isDetected: Bool { confidence >= Joint.minimumConfidence }
}

// MARK: - BodyPose

/// A snapshot of all tracked body joints for a single video frame.
///
/// Joints are stored in a dictionary keyed by `JointName` for O(1) lookup.
/// Convenience subscript and computed properties expose the most commonly
/// used joints directly.
///
/// **Coordinate system**
/// All positions use Vision's normalised coordinate space:
/// - Origin (0, 0) at the **bottom-left** of the image.
/// - (1, 1) at the **top-right**.
///
/// Convert to UIKit/SwiftUI coordinates (origin top-left) with
/// `CGPoint(x: joint.position.x, y: 1 - joint.position.y)`.
struct BodyPose {

    // MARK: - Storage

    /// All joints indexed by name. Always contains an entry for every
    /// `JointName` case; undetected joints have `isDetected == false`.
    let joints: [JointName: Joint]

    /// Timestamp of the source video frame (seconds since device boot),
    /// taken from `CMSampleBuffer.presentationTimeStamp`.
    let timestamp: Double

    // MARK: - Init

    init(joints: [JointName: Joint], timestamp: Double) {
        self.joints = joints
        self.timestamp = timestamp
    }

    // MARK: - Subscript

    /// Returns the joint for `name`, or `nil` if it was not present in the
    /// Vision observation (should not happen with a fully populated pose).
    subscript(name: JointName) -> Joint? { joints[name] }

    // MARK: - Convenience Accessors

    var leftShoulder:  Joint? { joints[.leftShoulder] }
    var rightShoulder: Joint? { joints[.rightShoulder] }
    var leftElbow:     Joint? { joints[.leftElbow] }
    var rightElbow:    Joint? { joints[.rightElbow] }
    var leftWrist:     Joint? { joints[.leftWrist] }
    var rightWrist:    Joint? { joints[.rightWrist] }
    var leftHip:       Joint? { joints[.leftHip] }
    var rightHip:      Joint? { joints[.rightHip] }
    var leftKnee:      Joint? { joints[.leftKnee] }
    var rightKnee:     Joint? { joints[.rightKnee] }

    // MARK: - Helpers

    /// All joints that pass the confidence threshold.
    var detectedJoints: [Joint] {
        joints.values.filter(\.isDetected)
    }

    /// `true` when every joint required for push-up detection is detected.
    var isValidForPushUpDetection: Bool {
        let required: [JointName] = [
            .leftShoulder, .rightShoulder,
            .leftElbow,    .rightElbow,
            .leftWrist,    .rightWrist
        ]
        return required.allSatisfy { joints[$0]?.isDetected == true }
    }
}

// MARK: - BodyPose + Skeleton Connections

extension BodyPose {

    /// Pairs of joints that should be connected by a line in the debug overlay.
    ///
    /// Each tuple represents one bone segment. Only pairs where both joints
    /// are detected will be drawn.
    static let skeletonConnections: [(JointName, JointName)] = [
        // Arms
        (.leftShoulder,  .leftElbow),
        (.leftElbow,     .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow,    .rightWrist),
        // Torso
        (.leftShoulder,  .rightShoulder),
        (.leftHip,       .rightHip),
        (.leftShoulder,  .leftHip),
        (.rightShoulder, .rightHip),
        // Legs
        (.leftHip,       .leftKnee),
        (.rightHip,      .rightKnee),
    ]
}
