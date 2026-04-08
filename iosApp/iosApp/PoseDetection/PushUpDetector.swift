import CoreGraphics
import Foundation

// MARK: - PushUpTrackingView

enum PushUpTrackingView: String, Sendable, Equatable {
    case unknown
    case side
    case front

    var displayName: String {
        switch self {
        case .unknown: return "Detecting"
        case .side: return "Side View"
        case .front: return "Front View"
        }
    }

    var supportsFormScoring: Bool {
        self == .side
    }
}

// MARK: - PushUpEvent

struct PushUpEvent: Sendable {
    let count: Int
    let elbowAngleAtCompletion: Double
    let timestamp: Double
    let trackingView: PushUpTrackingView
    let formScore: FormScore?
}

// MARK: - PushUpDetectorDelegate

protocol PushUpDetectorDelegate: AnyObject, Sendable {
    func pushUpDetector(_ detector: PushUpDetector, didCount event: PushUpEvent)
}

// MARK: - PushUpDetector

final class PushUpDetector {

    struct MovementValidationConfiguration: Sendable {
        let maxSideBodyLineDeviation: Double
        let minimumSideTorsoDrop: CGFloat
        let minimumFrontShoulderDrop: CGFloat
        let topPositionAngleThreshold: Double
        let maxInvalidDownFrames: Int
        let viewConfirmationFrames: Int
        let maxFrontAlignmentOffset: CGFloat
        let maxFrontAngleAsymmetry: Double
        let minFrontShoulderWidth: CGFloat
        let minFrontHipWidth: CGFloat

        static let `default` = MovementValidationConfiguration(
            maxSideBodyLineDeviation: 28.0,
            minimumSideTorsoDrop: 0.035,
            minimumFrontShoulderDrop: 0.022,
            topPositionAngleThreshold: 150.0,
            maxInvalidDownFrames: 6,
            viewConfirmationFrames: 4,
            maxFrontAlignmentOffset: 0.10,
            maxFrontAngleAsymmetry: 28.0,
            minFrontShoulderWidth: 0.18,
            minFrontHipWidth: 0.12
        )
    }

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

    var pushUpCount: Int { stateMachine.pushUpCount }
    var halfRepCount: Int { stateMachine.halfRepCount }
    var currentPhase: PushUpPhase { stateMachine.phase }
    private(set) var currentElbowAngle: Double?
    private(set) var bodyLineDeviation: Double?
    private(set) var positionState = PositionState()
    private(set) var currentTrackingView: PushUpTrackingView = .unknown

    private let stateMachine: PushUpStateMachine
    private let formScorer: FormScorer
    private let positionClassifier = PositionClassifier()
    private let smoother = SkeletonSmoother()
    private let stateMachineConfiguration: PushUpStateMachine.Configuration
    private let movementValidationConfiguration: MovementValidationConfiguration

    private(set) var smoothedPose: BodyPose?

    private var topReferenceY: CGFloat?
    private var minReferenceYInRep: CGFloat?
    private var hasReachedRequiredDepth = false
    private var invalidDownFrameCount = 0
    private var motionTrackingView: PushUpTrackingView = .unknown
    private var sideViewFrameCount = 0
    private var frontViewFrameCount = 0

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

        let previousTrackingView = currentTrackingView
        updateTrackingView(pose: pose, leftElbowAngle: leftAngle, rightElbowAngle: rightAngle)
        if previousTrackingView != currentTrackingView, stateMachine.phase == .down {
            invalidateCurrentRep()
        }

        let isPoseEligibleForRepTracking: Bool
        switch currentTrackingView {
        case .side:
            isPoseEligibleForRepTracking = isEligibleSidePose(pose: pose, angle: angle)
        case .front:
            isPoseEligibleForRepTracking = isEligibleFrontPose(
                pose: pose,
                angle: angle,
                leftElbowAngle: leftAngle,
                rightElbowAngle: rightAngle
            )
        case .unknown:
            isPoseEligibleForRepTracking = false
        }

        updateMotionTracking(
            referenceY: motionReferenceY(for: pose, trackingView: currentTrackingView),
            angle: angle,
            trackingView: currentTrackingView,
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
                   !hasReachedRequiredDepth {
                    invalidateCurrentRep()
                }
            }
        } else {
            invalidDownFrameCount = 0
        }

        let isInDownPhase = stateMachine.phase == .down
        let counted = stateMachine.update(angle: isPoseEligibleForRepTracking ? angle : nil)

        if currentTrackingView.supportsFormScoring {
            formScorer.recordFrame(
                pose: pose,
                leftElbowAngle: leftAngle,
                rightElbowAngle: rightAngle,
                isInDownPhase: isInDownPhase
            )
        } else if !isInDownPhase {
            formScorer.reset()
        }

        if counted {
            guard let completionAngle = angle, let pose else {
                assertionFailure("angle and pose must be non-nil when a push-up is counted")
                formScorer.reset()
                return
            }

            let score = currentTrackingView.supportsFormScoring ? formScorer.finalisePushUp() : nil
            let event = PushUpEvent(
                count: stateMachine.pushUpCount,
                elbowAngleAtCompletion: completionAngle,
                timestamp: pose.timestamp,
                trackingView: currentTrackingView,
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
        currentTrackingView = .unknown
        smoothedPose = nil
        sideViewFrameCount = 0
        frontViewFrameCount = 0
        resetRepMotionTracking()
    }

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

    static func computeShoulderCenterY(pose: BodyPose?) -> CGFloat? {
        midpoint(pose?.leftShoulder, pose?.rightShoulder)?.y
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

    private func updateTrackingView(
        pose: BodyPose?,
        leftElbowAngle: Double?,
        rightElbowAngle: Double?
    ) {
        let sideCandidate = isLikelySideView(pose: pose)
        let frontCandidate = isLikelyFrontView(
            pose: pose,
            leftElbowAngle: leftElbowAngle,
            rightElbowAngle: rightElbowAngle
        )

        switch (sideCandidate, frontCandidate) {
        case (true, false):
            sideViewFrameCount = min(
                sideViewFrameCount + 1,
                movementValidationConfiguration.viewConfirmationFrames
            )
            frontViewFrameCount = max(frontViewFrameCount - 1, 0)

        case (false, true):
            frontViewFrameCount = min(
                frontViewFrameCount + 1,
                movementValidationConfiguration.viewConfirmationFrames
            )
            sideViewFrameCount = max(sideViewFrameCount - 1, 0)

        case (true, true):
            if currentTrackingView == .front {
                frontViewFrameCount = min(
                    frontViewFrameCount + 1,
                    movementValidationConfiguration.viewConfirmationFrames
                )
                sideViewFrameCount = max(sideViewFrameCount - 1, 0)
            } else {
                sideViewFrameCount = min(
                    sideViewFrameCount + 1,
                    movementValidationConfiguration.viewConfirmationFrames
                )
                frontViewFrameCount = max(frontViewFrameCount - 1, 0)
            }

        case (false, false):
            sideViewFrameCount = max(sideViewFrameCount - 1, 0)
            frontViewFrameCount = max(frontViewFrameCount - 1, 0)
        }

        if sideViewFrameCount >= movementValidationConfiguration.viewConfirmationFrames {
            currentTrackingView = .side
        } else if frontViewFrameCount >= movementValidationConfiguration.viewConfirmationFrames {
            currentTrackingView = .front
        } else if sideViewFrameCount == 0 && frontViewFrameCount == 0 {
            currentTrackingView = .unknown
        }
    }

    private func isLikelySideView(pose: BodyPose?) -> Bool {
        guard
            let pose,
            Self.hasRequiredTorsoJoints(pose: pose),
            let shoulderMidpoint = Self.midpoint(pose.leftShoulder, pose.rightShoulder),
            let hipMidpoint = Self.midpoint(pose.leftHip, pose.rightHip),
            let bodyLineDeviation
        else { return false }

        return
            abs(shoulderMidpoint.y - hipMidpoint.y) <= 0.15 &&
            bodyLineDeviation <= movementValidationConfiguration.maxSideBodyLineDeviation
    }

    private func isLikelyFrontView(
        pose: BodyPose?,
        leftElbowAngle: Double?,
        rightElbowAngle: Double?
    ) -> Bool {
        guard let pose else { return false }
        guard
            let leftShoulder = pose.leftShoulder, leftShoulder.isDetected,
            let rightShoulder = pose.rightShoulder, rightShoulder.isDetected,
            let leftHip = pose.leftHip, leftHip.isDetected,
            let rightHip = pose.rightHip, rightHip.isDetected,
            let leftWrist = pose.leftWrist, leftWrist.isDetected,
            let rightWrist = pose.rightWrist, rightWrist.isDetected,
            let shoulderMidpoint = Self.midpoint(pose.leftShoulder, pose.rightShoulder),
            let hipMidpoint = Self.midpoint(pose.leftHip, pose.rightHip)
        else { return false }

        let shoulderWidth = abs(leftShoulder.position.x - rightShoulder.position.x)
        let hipWidth = abs(leftHip.position.x - rightHip.position.x)
        let torsoHeight = abs(shoulderMidpoint.y - hipMidpoint.y)
        let wristsBelowShoulders =
            leftWrist.position.y < leftShoulder.position.y - 0.02 &&
            rightWrist.position.y < rightShoulder.position.y - 0.02
        let isAligned =
            abs(shoulderMidpoint.x - hipMidpoint.x) <= movementValidationConfiguration.maxFrontAlignmentOffset
        let isSymmetric: Bool
        if let leftElbowAngle, let rightElbowAngle {
            isSymmetric = abs(leftElbowAngle - rightElbowAngle) <= movementValidationConfiguration.maxFrontAngleAsymmetry
        } else {
            isSymmetric = false
        }

        return
            !positionState.isHorizontal &&
            shoulderMidpoint.y > hipMidpoint.y + 0.02 &&
            shoulderWidth >= movementValidationConfiguration.minFrontShoulderWidth &&
            hipWidth >= movementValidationConfiguration.minFrontHipWidth &&
            torsoHeight >= 0.08 &&
            wristsBelowShoulders &&
            isAligned &&
            isSymmetric
    }

    private func isEligibleSidePose(pose: BodyPose?, angle: Double?) -> Bool {
        guard pose != nil, angle != nil else { return false }
        guard Self.hasRequiredArmJoints(pose: pose) else { return false }
        guard Self.hasRequiredTorsoJoints(pose: pose) else { return false }
        return isLikelySideView(pose: pose)
    }

    private func isEligibleFrontPose(
        pose: BodyPose?,
        angle: Double?,
        leftElbowAngle: Double?,
        rightElbowAngle: Double?
    ) -> Bool {
        guard pose != nil, angle != nil else { return false }
        return isLikelyFrontView(
            pose: pose,
            leftElbowAngle: leftElbowAngle,
            rightElbowAngle: rightElbowAngle
        )
    }

    private func motionReferenceY(
        for pose: BodyPose?,
        trackingView: PushUpTrackingView
    ) -> CGFloat? {
        switch trackingView {
        case .side:
            return Self.computeTorsoCenterY(pose: pose)
        case .front:
            return Self.computeShoulderCenterY(pose: pose)
        case .unknown:
            return nil
        }
    }

    private func requiredDepth(for trackingView: PushUpTrackingView) -> CGFloat {
        switch trackingView {
        case .side:
            return movementValidationConfiguration.minimumSideTorsoDrop
        case .front:
            return movementValidationConfiguration.minimumFrontShoulderDrop
        case .unknown:
            return .greatestFiniteMagnitude
        }
    }

    private func updateMotionTracking(
        referenceY: CGFloat?,
        angle: Double?,
        trackingView: PushUpTrackingView,
        isPoseEligibleForRepTracking: Bool
    ) {
        guard isPoseEligibleForRepTracking, let referenceY, trackingView != .unknown else {
            if stateMachine.phase != .down {
                resetRepMotionTracking()
            }
            return
        }

        switch stateMachine.phase {
        case .idle:
            if let angle, angle >= movementValidationConfiguration.topPositionAngleThreshold {
                topReferenceY = max(topReferenceY ?? referenceY, referenceY)
                minReferenceYInRep = nil
                hasReachedRequiredDepth = false
                motionTrackingView = trackingView
            }

        case .down:
            if motionTrackingView != trackingView {
                invalidateCurrentRep()
                return
            }

            minReferenceYInRep = min(minReferenceYInRep ?? referenceY, referenceY)

            if let topReferenceY, let minReferenceYInRep {
                hasReachedRequiredDepth =
                    (topReferenceY - minReferenceYInRep) >= requiredDepth(for: trackingView)
            }

        case .cooldown:
            minReferenceYInRep = nil
            hasReachedRequiredDepth = false
        }
    }

    private func invalidateCurrentRep() {
        stateMachine.cancelCurrentRep()
        formScorer.reset()
        resetRepMotionTracking()
    }

    private func resetRepMotionTracking() {
        topReferenceY = nil
        minReferenceYInRep = nil
        hasReachedRequiredDepth = false
        invalidDownFrameCount = 0
        motionTrackingView = .unknown
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
