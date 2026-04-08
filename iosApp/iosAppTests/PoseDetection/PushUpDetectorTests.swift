import CoreGraphics
import Testing

@testable import iosApp

// MARK: - Test Helpers

/// Builds a side-view push-up pose with configurable elbow bend and torso drop.
private func makePose(
    leftAngle: Double,
    rightAngle: Double,
    torsoDrop: CGFloat = 0,
    bodyLineBend: CGFloat = 0,
    confidence: Float = 0.9,
    timestamp: Double = 0
) -> BodyPose {
    func armJoints(
        angleDeg: Double,
        xOffset: Double,
        shoulderY: CGFloat,
        elbowY: CGFloat,
        shoulderName: JointName,
        elbowName: JointName,
        wristName: JointName
    ) -> (shoulder: Joint, elbow: Joint, wrist: Joint) {
        let rad = angleDeg * .pi / 180.0
        let elbowPos = CGPoint(x: xOffset, y: elbowY)
        let shoulderPos = CGPoint(x: xOffset, y: shoulderY)
        let wristPos = CGPoint(
            x: xOffset + sin(rad) * 0.11,
            y: elbowY - cos(rad) * 0.11
        )
        return (
            Joint(name: shoulderName, position: shoulderPos, confidence: confidence),
            Joint(name: elbowName,    position: elbowPos,    confidence: confidence),
            Joint(name: wristName,    position: wristPos,    confidence: confidence)
        )
    }

    let shoulderY = 0.62 - torsoDrop
    let elbowY = 0.54 - torsoDrop
    let hipY = 0.58 - torsoDrop
    let ankleY = 0.56 - torsoDrop + bodyLineBend

    let left = armJoints(
        angleDeg: leftAngle,
        xOffset: 0.35,
        shoulderY: shoulderY,
        elbowY: elbowY,
        shoulderName: .leftShoulder,
        elbowName: .leftElbow,
        wristName: .leftWrist
    )
    let right = armJoints(
        angleDeg: rightAngle,
        xOffset: 0.65,
        shoulderY: shoulderY,
        elbowY: elbowY,
        shoulderName: .rightShoulder,
        elbowName: .rightElbow,
        wristName: .rightWrist
    )

    var dict: [JointName: Joint] = Dictionary(
        uniqueKeysWithValues: JointName.allCases.map { name in
            (name, Joint(name: name, position: .zero, confidence: 0))
        }
    )
    dict[.leftShoulder]  = left.shoulder
    dict[.leftElbow]     = left.elbow
    dict[.leftWrist]     = left.wrist
    dict[.rightShoulder] = right.shoulder
    dict[.rightElbow]    = right.elbow
    dict[.rightWrist]    = right.wrist
    dict[.leftHip]       = Joint(name: .leftHip, position: CGPoint(x: 0.42, y: hipY), confidence: confidence)
    dict[.rightHip]      = Joint(name: .rightHip, position: CGPoint(x: 0.58, y: hipY), confidence: confidence)
    dict[.leftAnkle]     = Joint(name: .leftAnkle, position: CGPoint(x: 0.18, y: ankleY), confidence: confidence)
    dict[.rightAnkle]    = Joint(name: .rightAnkle, position: CGPoint(x: 0.82, y: ankleY), confidence: confidence)

    return BodyPose(joints: dict, timestamp: timestamp)
}

/// Feeds `frames` identical frames at the given angle into `detector`.
private func feed(
    _ detector: PushUpDetector,
    angle: Double,
    frames: Int,
    torsoDrop: CGFloat = 0,
    bodyLineBend: CGFloat = 0,
    startTimestamp: Double = 0
) {
    for i in 0..<frames {
        detector.process(
            makePose(leftAngle: angle, rightAngle: angle,
                     torsoDrop: torsoDrop,
                     bodyLineBend: bodyLineBend,
                     timestamp: startTimestamp + Double(i))
        )
    }
}

private func feedValidRep(
    _ detector: PushUpDetector,
    startTimestamp: Double = 0
) {
    feed(detector, angle: 170, frames: 3, torsoDrop: 0, startTimestamp: startTimestamp)
    feed(detector, angle: 70, frames: 3, torsoDrop: 0.08, startTimestamp: startTimestamp + 3)
    feed(detector, angle: 170, frames: 3, torsoDrop: 0, startTimestamp: startTimestamp + 6)
}

/// Feeds `frames` nil frames (no pose detected) into `detector`.
private func feedNil(_ detector: PushUpDetector, frames: Int) {
    for _ in 0..<frames { detector.process(nil) }
}

/// A standard tight configuration used across most integration tests.
private let testConfig = PushUpStateMachine.Configuration(
    downAngleThreshold: 90,
    upAngleThreshold: 160,
    hysteresisFrameCount: 3,
    cooldownFrameCount: 5
)

/// Records all received `PushUpEvent` values.
///
/// `@unchecked Sendable` is safe here because tests are single-threaded
/// and the delegate is only accessed from the test queue.
private final class RecordingDelegate: PushUpDetectorDelegate, @unchecked Sendable {
    var events: [PushUpEvent] = []
    func pushUpDetector(_ detector: PushUpDetector, didCount event: PushUpEvent) {
        events.append(event)
    }
}

// MARK: - PushUpDetectorTests

@Suite("PushUpDetector")
struct PushUpDetectorTests {

    // MARK: - Angle Calculation

    @Suite("Elbow angle calculation")
    struct AngleCalculation {

        @Test("Straight arm (collinear joints) returns ~180 degrees")
        func straightArm() throws {
            let shoulder = Joint(name: .leftShoulder, position: CGPoint(x: 0.5, y: 0.8), confidence: 0.9)
            let elbow    = Joint(name: .leftElbow,    position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            let wrist    = Joint(name: .leftWrist,    position: CGPoint(x: 0.5, y: 0.2), confidence: 0.9)
            let angle = try #require(PushUpDetector.elbowAngle(shoulder: shoulder, elbow: elbow, wrist: wrist))
            #expect(abs(angle - 180.0) < 0.5, "Expected ~180, got \(angle)")
        }

        @Test("Right-angle arm returns ~90 degrees")
        func rightAngle() throws {
            let shoulder = Joint(name: .leftShoulder, position: CGPoint(x: 0.5, y: 0.8), confidence: 0.9)
            let elbow    = Joint(name: .leftElbow,    position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            let wrist    = Joint(name: .leftWrist,    position: CGPoint(x: 0.8, y: 0.5), confidence: 0.9)
            let angle = try #require(PushUpDetector.elbowAngle(shoulder: shoulder, elbow: elbow, wrist: wrist))
            #expect(abs(angle - 90.0) < 0.5, "Expected ~90, got \(angle)")
        }

        @Test("Returns nil when a joint is below confidence threshold")
        func lowConfidenceJoint() {
            let shoulder = Joint(name: .leftShoulder, position: CGPoint(x: 0.5, y: 0.8), confidence: 0.1)
            let elbow    = Joint(name: .leftElbow,    position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            let wrist    = Joint(name: .leftWrist,    position: CGPoint(x: 0.5, y: 0.2), confidence: 0.9)
            #expect(PushUpDetector.elbowAngle(shoulder: shoulder, elbow: elbow, wrist: wrist) == nil)
        }

        @Test("Returns nil when a joint is nil")
        func nilJoint() {
            let elbow = Joint(name: .leftElbow, position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            let wrist = Joint(name: .leftWrist, position: CGPoint(x: 0.5, y: 0.2), confidence: 0.9)
            #expect(PushUpDetector.elbowAngle(shoulder: nil, elbow: elbow, wrist: wrist) == nil)
        }

        @Test("angleBetween returns nil for degenerate zero-length vector")
        func degenerateVector() {
            let p = CGPoint(x: 0.5, y: 0.5)
            #expect(PushUpDetector.angleBetween(a: p, vertex: p, b: CGPoint(x: 0.5, y: 0.2)) == nil)
        }

        @Test("Averaged angle uses both sides when both are detected")
        func averagesBothSides() throws {
            let pose = makePose(leftAngle: 90, rightAngle: 180)
            let angle = try #require(PushUpDetector.computeElbowAngle(from: pose))
            #expect(abs(angle - 135.0) < 1.0, "Expected ~135, got \(angle)")
        }

        @Test("Uses only left side when right side is undetected")
        func usesLeftWhenRightMissing() throws {
            var dict: [JointName: Joint] = Dictionary(
                uniqueKeysWithValues: JointName.allCases.map { name in
                    (name, Joint(name: name, position: .zero, confidence: 0))
                }
            )
            dict[.leftShoulder] = Joint(name: .leftShoulder, position: CGPoint(x: 0.5, y: 0.8), confidence: 0.9)
            dict[.leftElbow]    = Joint(name: .leftElbow,    position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            dict[.leftWrist]    = Joint(name: .leftWrist,    position: CGPoint(x: 0.5, y: 0.2), confidence: 0.9)
            let pose = BodyPose(joints: dict, timestamp: 0)
            let angle = try #require(PushUpDetector.computeElbowAngle(from: pose))
            #expect(abs(angle - 180.0) < 0.5)
        }

        @Test("Uses only right side when left side is undetected")
        func usesRightWhenLeftMissing() throws {
            var dict: [JointName: Joint] = Dictionary(
                uniqueKeysWithValues: JointName.allCases.map { name in
                    (name, Joint(name: name, position: .zero, confidence: 0))
                }
            )
            dict[.rightShoulder] = Joint(name: .rightShoulder, position: CGPoint(x: 0.5, y: 0.8), confidence: 0.9)
            dict[.rightElbow]    = Joint(name: .rightElbow,    position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            dict[.rightWrist]    = Joint(name: .rightWrist,    position: CGPoint(x: 0.5, y: 0.2), confidence: 0.9)
            let pose = BodyPose(joints: dict, timestamp: 0)
            let angle = try #require(PushUpDetector.computeElbowAngle(from: pose))
            #expect(abs(angle - 180.0) < 0.5)
        }

        @Test("Returns nil when pose is nil")
        func nilPose() {
            #expect(PushUpDetector.computeElbowAngle(from: nil) == nil)
        }

        @Test("makePose helper produces accurate angles across the range")
        func makePoseAccuracy() throws {
            for targetAngle in stride(from: 10.0, through: 170.0, by: 10.0) {
                let pose = makePose(leftAngle: targetAngle, rightAngle: targetAngle)
                let computed = try #require(PushUpDetector.computeElbowAngle(from: pose))
                #expect(abs(computed - targetAngle) < 1.0,
                        "Expected ~\(targetAngle), got \(computed)")
            }
        }
    }

    // MARK: - State Machine Integration

    @Suite("State machine integration")
    struct StateMachineIntegration {

        @Test("No push-up counted without DOWN phase")
        func noPushUpWithoutDown() {
            let detector = PushUpDetector(configuration: testConfig)
            feed(detector, angle: 170, frames: 10)
            #expect(detector.pushUpCount == 0)
            #expect(detector.currentPhase == .idle)
        }

        @Test("No push-up counted for partial cycle (DOWN only, no UP)")
        func halfPushUpNotCounted() {
            let detector = PushUpDetector(configuration: testConfig)
            feed(detector, angle: 170, frames: 3)
            feed(detector, angle: 70, frames: 3, torsoDrop: 0.08)
            #expect(detector.currentPhase == .down)
            feed(detector, angle: 70, frames: 5, torsoDrop: 0.08)
            #expect(detector.pushUpCount == 0)
        }

        @Test("One complete push-up is counted")
        func onePushUp() {
            let detector = PushUpDetector(configuration: testConfig)
            feed(detector, angle: 170, frames: 3)
            feed(detector, angle: 70, frames: 3, torsoDrop: 0.08)
            #expect(detector.currentPhase == .down)
            feed(detector, angle: 170, frames: 3)
            #expect(detector.pushUpCount == 1)
        }

        @Test("Push-up is counted even without a delegate")
        func countWithoutDelegate() {
            let detector = PushUpDetector(configuration: testConfig)
            feedValidRep(detector)
            #expect(detector.pushUpCount == 1)
        }

        @Test("Multiple push-ups are counted correctly")
        func multiplePushUps() {
            let detector = PushUpDetector(configuration: testConfig)
            for _ in 0..<5 {
                feedValidRep(detector)
                feed(detector, angle: 170, frames: 5)
            }
            #expect(detector.pushUpCount == 5)
        }

        @Test("Hysteresis prevents counting on brief angle dip below DOWN threshold")
        func hysteresisPreventsFalseDownTransition() {
            let detector = PushUpDetector(configuration: testConfig)
            feed(detector, angle: 170, frames: 3)
            feed(detector, angle: 70, frames: 2, torsoDrop: 0.08)
            #expect(detector.currentPhase == .idle, "Should still be idle after only 2 frames")
            #expect(detector.pushUpCount == 0)
        }

        @Test("Hysteresis prevents counting on brief angle rise above UP threshold")
        func hysteresisPreventsFalseUpTransition() {
            let detector = PushUpDetector(configuration: testConfig)
            feed(detector, angle: 170, frames: 3)
            feed(detector, angle: 70, frames: 3, torsoDrop: 0.08)
            #expect(detector.currentPhase == .down)
            feed(detector, angle: 170, frames: 2)
            #expect(detector.pushUpCount == 0, "Should not count with only 2 UP frames")
        }

        @Test("Cooldown prevents double-counting within cooldown window")
        func cooldownPreventsDuplicateCount() {
            let detector = PushUpDetector(configuration: testConfig)
            feedValidRep(detector)
            #expect(detector.pushUpCount == 1)
            feed(detector, angle: 170, frames: 1)
            feed(detector, angle: 70,  frames: 3, torsoDrop: 0.08)
            feed(detector, angle: 170, frames: 3)
            #expect(detector.pushUpCount == 1, "Should not count during cooldown")
        }

        @Test("Second push-up is counted after cooldown expires")
        func secondPushUpAfterCooldown() {
            let detector = PushUpDetector(configuration: testConfig)
            feedValidRep(detector)
            #expect(detector.pushUpCount == 1)
            feed(detector, angle: 170, frames: 5)
            #expect(detector.currentPhase == .idle)
            feedValidRep(detector, startTimestamp: 20)
            #expect(detector.pushUpCount == 2)
        }

        @Test("Nil pose frames reset pending counter and do not advance hysteresis")
        func nilPoseResetsHysteresis() {
            let detector = PushUpDetector(configuration: testConfig)
            feed(detector, angle: 170, frames: 3)
            feed(detector, angle: 70, frames: 2, torsoDrop: 0.08)
            feedNil(detector, frames: 1)
            feed(detector, angle: 70, frames: 1, torsoDrop: 0.08)
            #expect(detector.currentPhase == .idle)
        }

        @Test("Slow push-up (many frames per phase) is counted correctly")
        func slowPushUp() {
            let detector = PushUpDetector(configuration: testConfig)
            feed(detector, angle: 170, frames: 10)
            feed(detector, angle: 60,  frames: 30, torsoDrop: 0.08)
            #expect(detector.currentPhase == .down)
            feed(detector, angle: 170, frames: 30)
            #expect(detector.pushUpCount == 1)
        }

        @Test("Fast push-ups at minimum frame count are counted correctly")
        func fastPushUps() {
            let detector = PushUpDetector(configuration: testConfig)
            for _ in 0..<3 {
                feedValidRep(detector)
                feed(detector, angle: 170, frames: 5)
            }
            #expect(detector.pushUpCount == 3)
        }

        @Test("Arm-only movement without torso drop does not count")
        func armOnlyMovementDoesNotCount() {
            let detector = PushUpDetector(configuration: testConfig)
            feed(detector, angle: 170, frames: 3)
            feed(detector, angle: 70, frames: 3, torsoDrop: 0)
            feed(detector, angle: 170, frames: 3, torsoDrop: 0)
            #expect(detector.pushUpCount == 0)
            #expect(detector.halfRepCount == 1)
        }

        @Test("Noisy angle oscillation around DOWN threshold does not cause false count")
        func noisyAngleOscillation() {
            let detector = PushUpDetector(configuration: testConfig)
            for _ in 0..<20 {
                feed(detector, angle: 89, frames: 1)
                feed(detector, angle: 91, frames: 1)
            }
            #expect(detector.pushUpCount == 0)
            #expect(detector.currentPhase == .idle)
        }

        @Test("Reset clears count, phase, and currentElbowAngle")
        func resetClearsState() {
            let detector = PushUpDetector(configuration: testConfig)
            feedValidRep(detector)
            #expect(detector.pushUpCount == 1)
            detector.reset()
            #expect(detector.pushUpCount == 0)
            #expect(detector.currentPhase == .idle)
            #expect(detector.currentElbowAngle == nil)
        }

        @Test("Reset mid-DOWN clears state correctly")
        func resetMidDown() {
            let detector = PushUpDetector(configuration: testConfig)
            feed(detector, angle: 170, frames: 3)
            feed(detector, angle: 70, frames: 3, torsoDrop: 0.08)
            #expect(detector.currentPhase == .down)
            detector.reset()
            #expect(detector.currentPhase == .idle)
            #expect(detector.pushUpCount == 0)
            feedValidRep(detector, startTimestamp: 20)
            #expect(detector.pushUpCount == 1)
        }

        @Test("Reset mid-cooldown clears state correctly")
        func resetMidCooldown() {
            let detector = PushUpDetector(configuration: testConfig)
            feedValidRep(detector)
            #expect(detector.currentPhase == .cooldown)
            detector.reset()
            #expect(detector.currentPhase == .idle)
            #expect(detector.pushUpCount == 0)
        }
    }

    // MARK: - Delegate Callbacks

    @Suite("Delegate callbacks")
    struct DelegateCallbacks {

        @Test("Delegate receives one event per push-up with correct count")
        func delegateReceivesEvents() {
            let detector = PushUpDetector(configuration: testConfig)
            let delegate = RecordingDelegate()
            detector.delegate = delegate

            for _ in 0..<3 {
                feedValidRep(detector)
                feed(detector, angle: 170, frames: 5)
            }

            #expect(delegate.events.count == 3)
            #expect(delegate.events[0].count == 1)
            #expect(delegate.events[1].count == 2)
            #expect(delegate.events[2].count == 3)
        }

        @Test("Delegate event carries the correct frame timestamp")
        func delegateEventTimestamp() {
            let detector = PushUpDetector(configuration: testConfig)
            let delegate = RecordingDelegate()
            detector.delegate = delegate

            for i in 0..<3 {
                detector.process(makePose(leftAngle: 170, rightAngle: 170, timestamp: Double(i)))
            }
            for i in 0..<3 {
                detector.process(makePose(leftAngle: 70, rightAngle: 70, torsoDrop: 0.08, timestamp: 10.0 + Double(i)))
            }
            for i in 0..<3 {
                detector.process(makePose(leftAngle: 170, rightAngle: 170, timestamp: 20.0 + Double(i)))
            }

            #expect(delegate.events.count == 1)
            #expect(delegate.events[0].timestamp == 22.0)
        }

        @Test("Delegate event carries the correct elbow angle at completion")
        func delegateEventAngle() throws {
            let detector = PushUpDetector(configuration: testConfig)
            let delegate = RecordingDelegate()
            detector.delegate = delegate

            feed(detector, angle: 170, frames: 3)
            feed(detector, angle: 70,  frames: 3, torsoDrop: 0.08)
            feed(detector, angle: 165, frames: 3)

            let event = try #require(delegate.events.first)
            #expect(abs(event.elbowAngleAtCompletion - 165.0) < 1.0,
                    "Expected ~165, got \(event.elbowAngleAtCompletion)")
        }

        @Test("No delegate event when no push-up is counted")
        func noDelegateEventWithoutPushUp() {
            let detector = PushUpDetector(configuration: testConfig)
            let delegate = RecordingDelegate()
            detector.delegate = delegate
            feed(detector, angle: 170, frames: 30)
            #expect(delegate.events.isEmpty)
        }
    }

    // MARK: - PushUpStateMachine Direct Tests

    @Suite("PushUpStateMachine")
    struct StateMachineTests {

        @Test("Initial state is idle with zero count")
        func initialState() {
            let sm = PushUpStateMachine()
            #expect(sm.phase == .idle)
            #expect(sm.pushUpCount == 0)
        }

        @Test("Nil angle in idle does not change state")
        func nilAngleInIdle() {
            let sm = PushUpStateMachine()
            sm.update(angle: nil)
            #expect(sm.phase == .idle)
        }

        @Test("NaN angle is treated as nil (no state change)")
        func nanAngle() {
            let sm = PushUpStateMachine(configuration: testConfig)
            sm.update(angle: .nan)
            #expect(sm.phase == .idle)
            #expect(sm.pushUpCount == 0)
        }

        @Test("Positive infinity angle is treated as nil (no state change)")
        func positiveInfinityAngle() {
            let sm = PushUpStateMachine(configuration: testConfig)
            sm.update(angle: .infinity)
            #expect(sm.phase == .idle)
            #expect(sm.pushUpCount == 0)
        }

        @Test("Negative infinity angle is treated as nil (no state change)")
        func negativeInfinityAngle() {
            let sm = PushUpStateMachine(configuration: testConfig)
            sm.update(angle: -.infinity)
            #expect(sm.phase == .idle)
            #expect(sm.pushUpCount == 0)
        }

        @Test("NaN during DOWN phase does not advance UP counter")
        func nanDuringDown() {
            let config = PushUpStateMachine.Configuration(hysteresisFrameCount: 1, cooldownFrameCount: 1)
            let sm = PushUpStateMachine(configuration: config)
            sm.update(angle: 80)  // idle -> down
            #expect(sm.phase == .down)
            sm.update(angle: .nan)  // should not count
            #expect(sm.pushUpCount == 0)
            #expect(sm.phase == .down)
        }

        @Test("Transitions idle -> down after hysteresis")
        func idleToDown() {
            let config = PushUpStateMachine.Configuration(hysteresisFrameCount: 3)
            let sm = PushUpStateMachine(configuration: config)
            sm.update(angle: 80)
            sm.update(angle: 80)
            #expect(sm.phase == .idle, "Should not transition before hysteresisFrameCount")
            sm.update(angle: 80)
            #expect(sm.phase == .down)
        }

        @Test("Pending counter resets when condition breaks")
        func pendingCounterReset() {
            let config = PushUpStateMachine.Configuration(hysteresisFrameCount: 3)
            let sm = PushUpStateMachine(configuration: config)
            sm.update(angle: 80)
            sm.update(angle: 80)
            sm.update(angle: 100)
            sm.update(angle: 80)
            sm.update(angle: 80)
            #expect(sm.phase == .idle)
        }

        @Test("Cooldown counts down to idle over exactly cooldownFrameCount frames")
        func cooldownCountsDown() {
            let config = PushUpStateMachine.Configuration(
                hysteresisFrameCount: 1,
                cooldownFrameCount: 3
            )
            let sm = PushUpStateMachine(configuration: config)
            sm.update(angle: 80)
            sm.update(angle: 170)
            #expect(sm.phase == .cooldown)
            sm.update(angle: 170)
            #expect(sm.phase == .cooldown)
            sm.update(angle: 170)
            #expect(sm.phase == .cooldown)
            sm.update(angle: 170)
            #expect(sm.phase == .idle)
        }

        @Test("Extra frames during cooldown do not cause stuck state")
        func cooldownExtraFrames() {
            let config = PushUpStateMachine.Configuration(
                hysteresisFrameCount: 1,
                cooldownFrameCount: 2
            )
            let sm = PushUpStateMachine(configuration: config)
            sm.update(angle: 80)
            sm.update(angle: 170)
            #expect(sm.phase == .cooldown)
            // Feed more frames than cooldownFrameCount.
            for _ in 0..<10 {
                sm.update(angle: 170)
            }
            // Must be back in idle, not stuck.
            #expect(sm.phase == .idle)
        }

        @Test("Reset returns machine to initial state")
        func resetMachine() {
            let config = PushUpStateMachine.Configuration(hysteresisFrameCount: 1)
            let sm = PushUpStateMachine(configuration: config)
            sm.update(angle: 80)
            sm.update(angle: 170)
            #expect(sm.pushUpCount == 1)
            sm.reset()
            #expect(sm.phase == .idle)
            #expect(sm.pushUpCount == 0)
        }

        @Test("update returns true exactly when a push-up is counted")
        func updateReturnValue() {
            let config = PushUpStateMachine.Configuration(
                hysteresisFrameCount: 1,
                cooldownFrameCount: 1
            )
            let sm = PushUpStateMachine(configuration: config)
            let r1 = sm.update(angle: 80)
            let r2 = sm.update(angle: 170)
            let r3 = sm.update(angle: 170)
            #expect(r1 == false)
            #expect(r2 == true)
            #expect(r3 == false)
        }
    }
}
