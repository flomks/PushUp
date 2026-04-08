import CoreGraphics
import Foundation

// MARK: - PushUpEvent

struct PushUpEvent: Sendable {
    let count: Int
    let elbowAngleAtCompletion: Double
    let timestamp: Double
    let formScore: FormScore?
}

// MARK: - PushUpDetectorDelegate

protocol PushUpDetectorDelegate: AnyObject, Sendable {
    func pushUpDetector(_ detector: PushUpDetector, didCount event: PushUpEvent)
}

// MARK: - PushUpDetector

final class PushUpDetector {

    struct MovementValidationConfiguration: Sendable {
        /// Maximum allowed shoulder-hip-ankle deviation while a rep is tracked.
        let maxBodyLineDeviation: Double

        /// Minimum torso drop required between top and bottom of a rep.
        let minimumTorsoDrop: CGFloat

        /// Minimum elbow extension that qualifies as a valid top position.
        let topPositionAngleThreshold: Double

        /// Consecutive invalid frames tolerated while already in DOWN.
        let maxInvalidDownFrames: Int

        static let `default` = MovementValidationConfiguration(
            maxBodyLineDeviation: 28.0,
            minimumTorsoDrop: 0.035,
            topPositionAngleThreshold: 150.0,
            maxInvalidDownFrames: 6
        )
    }

    // MARK: - Delegate

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

    var pushUpCount: Int { stateMachine.pushUpCount }
    var halfRepCount: Int { stateMachine.halfRepCount }
    var currentPhase: PushUpPhase { stateMachine.phase }
    private(set) var currentElbowAngle: Double?
    private(set) var bodyLineDeviation: Double?
    private(set) var positionState = PositionState()

    // MARK: - Private

    private let stateMachine: PushUpStateMachine
    private let formScorer: FormScorer
    private let positionClassifier = PositionClassifier()
    private let smoother = SkeletonSmoother()
    private let stateMachineConfiguration: PushUpStateMachine.Configuration
    private let movementValidationConfiguration: MovementValidationConfiguration

    private(set) var smoothedPose: BodyPose?

    private var topTorsoCenterY: CGFloat?
    private var minTorsoCenterYInRep: CGFloat?
    private var hasReachedRequiredTorsoDepth = false
    private var invalidDownFrameCount = 0

    // MARK: - Init

    init(
        configuration: PushUpStateMachine.Configuration = .default,
        formScorerConfiguration: FormScorer.Configuration = .default,
        movementValidationConfiguration: MovementValidationConfiguration = .default
    ) {
        self.stateMachineConfiguration = configuration
        self.stateMachine = PushUpStateMachine(configuration: configuration)
        self.formScorer = FormScorer(configuration: formScorerConfiguration)
        self.movementValidationConfiguration = movementValidationConfiguration
    }

    // MARK: - Public API

    func process(_ pose: BodyPose?) {
        let leftAngle = Self.elbowAngle(
            shoulder: pose?.leftShoulder,
            elbow: pose?.leftElbow,
            wrist: pose?.leftWrist
        )
        let rightAngle = Self.elbowAngle(
            shoulder: pose?.rightShoulder,
            elbow: pose?.rightElbow,
            wrist: pose?.rightWrist
        )
        let angle = FormScorer.averagedAngle(left: leftAngle, right: rightAngle)
        currentElbowAngle = angle

        bodyLineDeviation = Self.computeBodyLineDeviation(pose: pose)
        positionState = positionClassifier.update(pose: pose)
        smoothedPose = smoother.smooth(pose)

        let torsoCenterY = Self.computeTorsoCenterY(pose: pose)
        let hasStableBodyLine =
            bodyLineDeviation.map { $0 <= movementValidationConfiguration.maxBodyLineDeviation }
            ?? false
        let isPoseEligibleForRepTracking =
            pose != nil &&
            angle != nil &&
            Self.hasRequiredArmJoints(pose: pose) &&
            Self.hasRequiredTorsoJoints(pose: pose) &&
            positionState.isHorizontal &&
            hasStableBodyLine

        updateTorsoMotionTracking(
            torsoCenterY: torsoCenterY,
            angle: angle,
            isPoseEligibleForRepTracking: isPoseEligibleForRepTracking
        )

        if stateMachine.phase == .down {
            if !isPoseEligibleForRepTracking {
                invalidDownFrameCount += 1
                if invalidDownFrameCount >= movementValidationConfiguration.maxInvalidDownFrames {
                    invalidateCurrentRep()
                }
            } else {
                invalidDownFrameCount = 0

                if let angle,
                   angle > stateMachineConfiguration.upAngleThreshold,
                   !hasReachedRequiredTorsoDepth {
                    invalidateCurrentRep()
                }
            }
        } else {
            invalidDownFrameCount = 0
        }

        let isInDownPhase = stateMachine.phase == .down
        let counted = stateMachine.update(angle: isPoseEligibleForRepTracking ? angle : nil)

        formScorer.recordFrame(
            pose: pose,
            leftElbowAngle: leftAngle,
            rightElbowAngle: rightAngle,
            isInDownPhase: isInDownPhase
        )

        if counted {
            guard let completionAngle = angle, let pose else {
                assertionFailure("angle and pose must be non-nil when a push-up is counted")
                formScorer.reset()
                return
            }

            let score = formScorer.finalisePushUp()
            let event = PushUpEvent(
                count: stateMachine.pushUpCount,
                elbowAngleAtCompletion: completionAngle,
                timestamp: pose.timestamp,
                formScore: score
            )
            resetRepMotionTracking()
            let currentDelegate = delegate
            currentDelegate?.pushUpDetector(self, didCount: event)
        }
    }

    func reset() {
        stateMachine.reset()
        formScorer.reset()
        positionClassifier.reset()
        smoother.reset()
        currentElbowAngle = nil
        bodyLineDeviation = nil
        positionState = PositionState()
        smoothedPose = nil
        resetRepMotionTracking()
    }

    // MARK: - Angle Computation

    static func computeElbowAngle(from pose: BodyPose?) -> Double? {
        guard let pose else { return nil }
        let left = elbowAngle(shoulder: pose.leftShoulder, elbow: pose.leftElbow, wrist: pose.leftWrist)
        let right = elbowAngle(shoulder: pose.rightShoulder, elbow: pose.rightElbow, wrist: pose.rightWrist)
        return FormScorer.averagedAngle(left: left, right: right)
    }

    static func elbowAngle(
        shoulder: Joint?,
        elbow: Joint?,
        wrist: Joint?
    ) -> Double? {
        guard
            let shoulder, shoulder.isDetected,
            let elbow, elbow.isDetected,
            let wrist, wrist.isDetected
        else { return nil }

        return angleBetween(
            a: shoulder.position,
            vertex: elbow.position,
            b: wrist.position
        )
    }

    // MARK: - Body Geometry

    static func computeBodyLineDeviation(pose: BodyPose?) -> Double? {
        guard let pose else { return nil }

        let leftAngle = angleBetween(
            a: pose.leftShoulder?.isDetected == true ? pose.leftShoulder!.position : nil,
            vertex: pose.leftHip?.isDetected == true ? pose.leftHip!.position : nil,
            b: pose.leftAnkle?.isDetected == true ? pose.leftAnkle!.position : nil
        )
        let rightAngle = angleBetween(
            a: pose.rightShoulder?.isDetected == true ? pose.rightShoulder!.position : nil,
            vertex: pose.rightHip?.isDetected == true ? pose.rightHip!.position : nil,
            b: pose.rightAnkle?.isDetected == true ? pose.rightAnkle!.position : nil
        )

        let avg = FormScorer.averagedAngle(left: leftAngle, right: rightAngle)
        guard let avg else { return nil }
        return abs(180.0 - avg)
    }

    static func computeTorsoCenterY(pose: BodyPose?) -> CGFloat? {
        guard
            let shoulderMidpoint = midpoint(pose?.leftShoulder, pose?.rightShoulder),
            let hipMidpoint = midpoint(pose?.leftHip, pose?.rightHip)
        else { return nil }

        return (shoulderMidpoint.y + hipMidpoint.y) / 2
    }

    private static func angleBetween(a: CGPoint?, vertex: CGPoint?, b: CGPoint?) -> Double? {
        guard let a, let vertex, let b else { return nil }
        return angleBetween(a: a, vertex: vertex, b: b)
    }

    static func angleBetween(a: CGPoint, vertex: CGPoint, b: CGPoint) -> Double? {
        let vax = Double(a.x - vertex.x)
        let vay = Double(a.y - vertex.y)
        let vbx = Double(b.x - vertex.x)
        let vby = Double(b.y - vertex.y)

        let magA = (vax * vax + vay * vay).squareRoot()
        let magB = (vbx * vbx + vby * vby).squareRoot()

        guard magA > 0, magB > 0 else { return nil }

        let dot = vax * vbx + vay * vby
        let cosAngle = max(-1.0, min(1.0, dot / (magA * magB)))
        return acos(cosAngle) * (180.0 / .pi)
    }

    // MARK: - Validation Helpers

    private func updateTorsoMotionTracking(
        torsoCenterY: CGFloat?,
        angle: Double?,
        isPoseEligibleForRepTracking: Bool
    ) {
        guard isPoseEligibleForRepTracking, let torsoCenterY else {
            if stateMachine.phase != .down {
                resetRepMotionTracking()
            }
            return
        }

        switch stateMachine.phase {
        case .idle:
            if let angle, angle >= movementValidationConfiguration.topPositionAngleThreshold {
                topTorsoCenterY = max(topTorsoCenterY ?? torsoCenterY, torsoCenterY)
                minTorsoCenterYInRep = nil
                hasReachedRequiredTorsoDepth = false
            }

        case .down:
            minTorsoCenterYInRep = min(minTorsoCenterYInRep ?? torsoCenterY, torsoCenterY)

            if let topTorsoCenterY, let minTorsoCenterYInRep {
                hasReachedRequiredTorsoDepth =
                    (topTorsoCenterY - minTorsoCenterYInRep) >= movementValidationConfiguration.minimumTorsoDrop
            }

        case .cooldown:
            minTorsoCenterYInRep = nil
            hasReachedRequiredTorsoDepth = false
        }
    }

    private func invalidateCurrentRep() {
        stateMachine.cancelCurrentRep()
        formScorer.reset()
        resetRepMotionTracking()
    }

    private func resetRepMotionTracking() {
        topTorsoCenterY = nil
        minTorsoCenterYInRep = nil
        hasReachedRequiredTorsoDepth = false
        invalidDownFrameCount = 0
    }

    private static func hasRequiredArmJoints(pose: BodyPose?) -> Bool {
        guard let pose else { return false }
        let required: [Joint?] = [
            pose.leftShoulder, pose.rightShoulder,
            pose.leftElbow, pose.rightElbow,
            pose.leftWrist, pose.rightWrist
        ]
        return required.allSatisfy { $0?.isDetected == true }
    }

    private static func hasRequiredTorsoJoints(pose: BodyPose?) -> Bool {
        guard let pose else { return false }
        let hasShoulders = midpoint(pose.leftShoulder, pose.rightShoulder) != nil
        let hasHips = midpoint(pose.leftHip, pose.rightHip) != nil
        let hasAnkle = [pose.leftAnkle, pose.rightAnkle].contains { $0?.isDetected == true }
        return hasShoulders && hasHips && hasAnkle
    }

    private static func midpoint(_ a: Joint?, _ b: Joint?) -> CGPoint? {
        let detectedA = a?.isDetected == true ? a : nil
        let detectedB = b?.isDetected == true ? b : nil

        switch (detectedA, detectedB) {
        case let (a?, b?):
            return CGPoint(
                x: (a.position.x + b.position.x) / 2,
                y: (a.position.y + b.position.y) / 2
            )
        case let (a?, nil):
            return a.position
        case let (nil, b?):
            return b.position
        case (nil, nil):
            return nil
        }
    }
}
