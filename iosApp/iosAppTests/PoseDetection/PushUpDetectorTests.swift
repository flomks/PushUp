import CoreGraphics
import Testing

@testable import iosApp

// MARK: - Test Helpers

/// Builds a `BodyPose` with all six arm joints set to produce the requested
/// elbow angles. All other joints are zero-confidence placeholders.
///
/// - Parameters:
///   - leftAngle:  Desired elbow angle on the left side (degrees).
///   - rightAngle: Desired elbow angle on the right side (degrees).
///   - confidence: Confidence applied to all six arm joints (default 0.9).
///   - timestamp:  Frame timestamp in seconds (default 0).
private func makePose(
    leftAngle: Double,
    rightAngle: Double,
    confidence: Float = 0.9,
    timestamp: Double = 0
) -> BodyPose {
    // Geometry: place the elbow at a fixed position, shoulder directly above,
    // and wrist at the desired angle from the shoulder-elbow axis.
    // Unit-length arm segments keep the expected angle exact.
    //
    // Coordinate system: Vision normalised (origin bottom-left, y up).
    func armJoints(
        angleDeg: Double,
        xOffset: Double,
        shoulderName: JointName,
        elbowName: JointName,
        wristName: JointName
    ) -> (shoulder: Joint, elbow: Joint, wrist: Joint) {
        let rad = angleDeg * .pi / 180.0
        let elbowPos   = CGPoint(x: xOffset, y: 0.5)
        let shoulderPos = CGPoint(x: xOffset, y: 0.6)          // directly above
        // Rotate the downward unit vector by `rad` around the elbow.
        let wristPos   = CGPoint(x: xOffset + sin(rad), y: 0.5 - cos(rad))
        return (
            Joint(name: shoulderName, position: shoulderPos, confidence: confidence),
            Joint(name: elbowName,    position: elbowPos,    confidence: confidence),
            Joint(name: wristName,    position: wristPos,    confidence: confidence)
        )
    }

    let left  = armJoints(angleDeg: leftAngle,  xOffset: 0.35,
                          shoulderName: .leftShoulder,  elbowName: .leftElbow,  wristName: .leftWrist)
    let right = armJoints(angleDeg: rightAngle, xOffset: 0.65,
                          shoulderName: .rightShoulder, elbowName: .rightElbow, wristName: .rightWrist)

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

    return BodyPose(joints: dict, timestamp: timestamp)
}

/// Feeds `frames` identical frames at the given angle into `detector`.
private func feed(
    _ detector: PushUpDetector,
    angle: Double,
    frames: Int,
    startTimestamp: Double = 0
) {
    for i in 0..<frames {
        detector.process(
            makePose(leftAngle: angle, rightAngle: angle,
                     timestamp: startTimestamp + Double(i))
        )
    }
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

// MARK: - PushUpDetectorTests

@Suite("PushUpDetector")
struct PushUpDetectorTests {

    // MARK: - Angle Calculation

    @Suite("Elbow angle calculation")
    struct AngleCalculation {

        @Test("Straight arm (collinear joints) returns ~180 degrees")
        func straightArm() throws {
            let detector = PushUpDetector()
            let shoulder = Joint(name: .leftShoulder, position: CGPoint(x: 0.5, y: 0.8), confidence: 0.9)
            let elbow    = Joint(name: .leftElbow,    position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            let wrist    = Joint(name: .leftWrist,    position: CGPoint(x: 0.5, y: 0.2), confidence: 0.9)
            let angle = try #require(detector.elbowAngle(shoulder: shoulder, elbow: elbow, wrist: wrist))
            #expect(abs(angle - 180.0) < 0.5, "Expected ~180°, got \(angle)°")
        }

        @Test("Right-angle arm returns ~90 degrees")
        func rightAngle() throws {
            let detector = PushUpDetector()
            let shoulder = Joint(name: .leftShoulder, position: CGPoint(x: 0.5, y: 0.8), confidence: 0.9)
            let elbow    = Joint(name: .leftElbow,    position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            let wrist    = Joint(name: .leftWrist,    position: CGPoint(x: 0.8, y: 0.5), confidence: 0.9)
            let angle = try #require(detector.elbowAngle(shoulder: shoulder, elbow: elbow, wrist: wrist))
            #expect(abs(angle - 90.0) < 0.5, "Expected ~90°, got \(angle)°")
        }

        @Test("Returns nil when a joint is below confidence threshold")
        func lowConfidenceJoint() {
            let detector = PushUpDetector()
            let shoulder = Joint(name: .leftShoulder, position: CGPoint(x: 0.5, y: 0.8), confidence: 0.1)
            let elbow    = Joint(name: .leftElbow,    position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            let wrist    = Joint(name: .leftWrist,    position: CGPoint(x: 0.5, y: 0.2), confidence: 0.9)
            #expect(detector.elbowAngle(shoulder: shoulder, elbow: elbow, wrist: wrist) == nil)
        }

        @Test("Returns nil when a joint is nil")
        func nilJoint() {
            let detector = PushUpDetector()
            let elbow = Joint(name: .leftElbow, position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            let wrist = Joint(name: .leftWrist, position: CGPoint(x: 0.5, y: 0.2), confidence: 0.9)
            #expect(detector.elbowAngle(shoulder: nil, elbow: elbow, wrist: wrist) == nil)
        }

        @Test("angleBetween returns nil for degenerate zero-length vector")
        func degenerateVector() {
            let detector = PushUpDetector()
            let p = CGPoint(x: 0.5, y: 0.5)
            #expect(detector.angleBetween(a: p, vertex: p, b: CGPoint(x: 0.5, y: 0.2)) == nil)
        }

        @Test("Averaged angle uses both sides when both are detected")
        func averagesBothSides() throws {
            let detector = PushUpDetector()
            // Left: 90°, right: 180° -> average = 135°
            let pose = makePose(leftAngle: 90, rightAngle: 180)
            let angle = try #require(detector.computeElbowAngle(from: pose))
            #expect(abs(angle - 135.0) < 1.0, "Expected ~135°, got \(angle)°")
        }

        @Test("Uses only left side when right side is undetected")
        func usesLeftWhenRightMissing() throws {
            let detector = PushUpDetector()
            var dict: [JointName: Joint] = Dictionary(
                uniqueKeysWithValues: JointName.allCases.map { name in
                    (name, Joint(name: name, position: .zero, confidence: 0))
                }
            )
            dict[.leftShoulder] = Joint(name: .leftShoulder, position: CGPoint(x: 0.5, y: 0.8), confidence: 0.9)
            dict[.leftElbow]    = Joint(name: .leftElbow,    position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            dict[.leftWrist]    = Joint(name: .leftWrist,    position: CGPoint(x: 0.5, y: 0.2), confidence: 0.9)
            let pose = BodyPose(joints: dict, timestamp: 0)
            let angle = try #require(detector.computeElbowAngle(from: pose))
            #expect(abs(angle - 180.0) < 0.5)
        }

        @Test("Returns nil when pose is nil")
        func nilPose() {
            let detector = PushUpDetector()
            #expect(detector.computeElbowAngle(from: nil) == nil)
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
            feed(detector, angle: 70, frames: 3)
            #expect(detector.currentPhase == .down)
            feed(detector, angle: 70, frames: 5)
            #expect(detector.pushUpCount == 0)
        }

        @Test("One complete push-up is counted")
        func onePushUp() {
            let detector = PushUpDetector(configuration: testConfig)
            feed(detector, angle: 70, frames: 3)
            #expect(detector.currentPhase == .down)
            feed(detector, angle: 170, frames: 3)
            #expect(detector.pushUpCount == 1)
        }

        @Test("Multiple push-ups are counted correctly")
        func multiplePushUps() {
            let detector = PushUpDetector(configuration: testConfig)
            for _ in 0..<5 {
                feed(detector, angle: 70,  frames: 3)
                feed(detector, angle: 170, frames: 3)
                feed(detector, angle: 170, frames: 5) // wait out cooldown
            }
            #expect(detector.pushUpCount == 5)
        }

        @Test("Hysteresis prevents counting on brief angle dip below DOWN threshold")
        func hysteresisPreventsFalseDownTransition() {
            let detector = PushUpDetector(configuration: testConfig)
            // Only 2 frames below threshold (hysteresisFrameCount = 3).
            feed(detector, angle: 70, frames: 2)
            #expect(detector.currentPhase == .idle, "Should still be idle after only 2 frames")
            #expect(detector.pushUpCount == 0)
        }

        @Test("Hysteresis prevents counting on brief angle rise above UP threshold")
        func hysteresisPreventsFalseUpTransition() {
            let detector = PushUpDetector(configuration: testConfig)
            // Enter DOWN phase.
            feed(detector, angle: 70, frames: 3)
            #expect(detector.currentPhase == .down)
            // Only 2 frames above UP threshold (hysteresisFrameCount = 3).
            feed(detector, angle: 170, frames: 2)
            #expect(detector.pushUpCount == 0, "Should not count with only 2 UP frames")
        }

        @Test("Cooldown prevents double-counting within cooldown window")
        func cooldownPreventsDuplicateCount() {
            let detector = PushUpDetector(configuration: testConfig)
            feed(detector, angle: 70,  frames: 3)
            feed(detector, angle: 170, frames: 3)
            #expect(detector.pushUpCount == 1)
            // Attempt another cycle immediately during cooldown.
            feed(detector, angle: 70,  frames: 3)
            feed(detector, angle: 170, frames: 3)
            #expect(detector.pushUpCount == 1, "Should not count during cooldown")
        }

        @Test("Second push-up is counted after cooldown expires")
        func secondPushUpAfterCooldown() {
            let detector = PushUpDetector(configuration: testConfig)
            feed(detector, angle: 70,  frames: 3)
            feed(detector, angle: 170, frames: 3)
            #expect(detector.pushUpCount == 1)
            feed(detector, angle: 170, frames: 5) // exhaust cooldown
            #expect(detector.currentPhase == .idle)
            feed(detector, angle: 70,  frames: 3)
            feed(detector, angle: 170, frames: 3)
            #expect(detector.pushUpCount == 2)
        }

        @Test("Nil pose frames reset pending counter and do not advance hysteresis")
        func nilPoseResetsHysteresis() {
            let detector = PushUpDetector(configuration: testConfig)
            // 2 frames below threshold, then nil, then 1 more below.
            feed(detector, angle: 70, frames: 2)
            feedNil(detector, frames: 1)   // resets pending counter
            feed(detector, angle: 70, frames: 1)
            // Counter was reset by nil; only 1 consecutive frame after -> still idle.
            #expect(detector.currentPhase == .idle)
        }

        @Test("Slow push-up (many frames per phase) is counted correctly")
        func slowPushUp() {
            let detector = PushUpDetector(configuration: testConfig)
            feed(detector, angle: 60,  frames: 30)
            #expect(detector.currentPhase == .down)
            feed(detector, angle: 170, frames: 30)
            #expect(detector.pushUpCount == 1)
        }

        @Test("Fast push-ups at minimum frame count are counted correctly")
        func fastPushUps() {
            let detector = PushUpDetector(configuration: testConfig)
            for _ in 0..<3 {
                feed(detector, angle: 70,  frames: 3)
                feed(detector, angle: 170, frames: 3)
                feed(detector, angle: 170, frames: 5) // cooldown
            }
            #expect(detector.pushUpCount == 3)
        }

        @Test("Noisy angle oscillation around DOWN threshold does not cause false count")
        func noisyAngleOscillation() {
            let detector = PushUpDetector(configuration: testConfig)
            // Alternate 89°/91° — never holds for 3 consecutive frames.
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
            feed(detector, angle: 70,  frames: 3)
            feed(detector, angle: 170, frames: 3)
            #expect(detector.pushUpCount == 1)
            detector.reset()
            #expect(detector.pushUpCount == 0)
            #expect(detector.currentPhase == .idle)
            #expect(detector.currentElbowAngle == nil)
        }
    }

    // MARK: - Delegate Callbacks

    @Suite("Delegate callbacks")
    struct DelegateCallbacks {

        /// Records all received `PushUpEvent` values.
        ///
        /// `@unchecked Sendable` is safe here because tests are single-threaded
        /// and the delegate is only accessed from the test queue.
        final class RecordingDelegate: PushUpDetectorDelegate, @unchecked Sendable {
            var events: [PushUpEvent] = []
            func pushUpDetector(_ detector: PushUpDetector, didCount event: PushUpEvent) {
                events.append(event)
            }
        }

        @Test("Delegate receives one event per push-up with correct count")
        func delegateReceivesEvents() {
            let detector = PushUpDetector(configuration: testConfig)
            let delegate = RecordingDelegate()
            detector.delegate = delegate

            for _ in 0..<3 {
                feed(detector, angle: 70,  frames: 3)
                feed(detector, angle: 170, frames: 3)
                feed(detector, angle: 170, frames: 5) // cooldown
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

            // DOWN frames at t=0, 1, 2.
            for i in 0..<3 {
                detector.process(makePose(leftAngle: 70, rightAngle: 70, timestamp: Double(i)))
            }
            // UP frames at t=10, 11, 12. The 3rd UP frame (t=12) triggers the count.
            for i in 0..<3 {
                detector.process(makePose(leftAngle: 170, rightAngle: 170, timestamp: 10.0 + Double(i)))
            }

            #expect(delegate.events.count == 1)
            #expect(delegate.events[0].timestamp == 12.0)
        }

        @Test("Delegate event carries the correct elbow angle at completion")
        func delegateEventAngle() throws {
            let detector = PushUpDetector(configuration: testConfig)
            let delegate = RecordingDelegate()
            detector.delegate = delegate

            feed(detector, angle: 70,  frames: 3)
            // UP frames at exactly 165°.
            feed(detector, angle: 165, frames: 3)

            let event = try #require(delegate.events.first)
            // Both arms at 165° -> averaged angle = 165°.
            #expect(abs(event.elbowAngleAtCompletion - 165.0) < 1.0,
                    "Expected ~165°, got \(event.elbowAngleAtCompletion)°")
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
            sm.update(angle: 100) // breaks the condition -> counter reset
            sm.update(angle: 80)
            sm.update(angle: 80)
            // Only 2 consecutive frames below threshold after the break.
            #expect(sm.phase == .idle)
        }

        @Test("Cooldown counts down to idle over exactly cooldownFrameCount frames")
        func cooldownCountsDown() {
            let config = PushUpStateMachine.Configuration(
                hysteresisFrameCount: 1,
                cooldownFrameCount: 3
            )
            let sm = PushUpStateMachine(configuration: config)
            sm.update(angle: 80)   // idle -> down
            sm.update(angle: 170)  // down -> cooldown (count = 1)
            #expect(sm.phase == .cooldown)
            sm.update(angle: 170)  // cooldown frame 1 (remaining: 2)
            #expect(sm.phase == .cooldown)
            sm.update(angle: 170)  // cooldown frame 2 (remaining: 1)
            #expect(sm.phase == .cooldown)
            sm.update(angle: 170)  // cooldown frame 3 (remaining: 0) -> idle
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
            let r1 = sm.update(angle: 80)   // idle -> down
            let r2 = sm.update(angle: 170)  // down -> cooldown (count!)
            let r3 = sm.update(angle: 170)  // cooldown -> idle
            #expect(r1 == false)
            #expect(r2 == true)
            #expect(r3 == false)
        }

        @Test("Configuration precondition: downThreshold must be less than upThreshold")
        func configurationInvalidThresholds() {
            #expect(
                performing: {
                    _ = PushUpStateMachine.Configuration(
                        downAngleThreshold: 160,
                        upAngleThreshold: 90
                    )
                },
                throws: { error in
                    // precondition failure manifests as a crash in release builds;
                    // in debug/test builds it throws a Swift runtime error.
                    // We just verify the precondition is enforced.
                    _ = error
                    return true
                }
            )
        }
    }
}
