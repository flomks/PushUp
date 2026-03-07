import CoreGraphics
import Testing

@testable import iosApp

// MARK: - Helpers

/// Builds a minimal `BodyPose` with only the six arm joints populated.
/// All other joints are inserted as zero-confidence placeholders so that
/// `BodyPose.isValidForPushUpDetection` behaves correctly.
///
/// - Parameters:
///   - leftAngle:  Desired elbow angle on the left side (degrees).
///   - rightAngle: Desired elbow angle on the right side (degrees).
///   - confidence: Confidence value applied to all six arm joints.
///   - timestamp:  Frame timestamp in seconds.
private func makePose(
    leftAngle: Double,
    rightAngle: Double,
    confidence: Float = 0.9,
    timestamp: Double = 0
) -> BodyPose {
    // Place the shoulder directly above the elbow, and the wrist at the
    // desired angle from the elbow.  We use unit-length arm segments so the
    // geometry is easy to reason about.
    //
    // Coordinate system: Vision normalised (origin bottom-left, y up).
    // The angle is measured at the elbow between the shoulder and wrist vectors.

    func joints(angle angleDeg: Double, xOffset: Double) -> (shoulder: Joint, elbow: Joint, wrist: Joint) {
        let angleRad = angleDeg * .pi / 180.0
        // Elbow at a fixed position.
        let elbowPos = CGPoint(x: xOffset, y: 0.5)
        // Shoulder is directly above the elbow (vector pointing up).
        let shoulderPos = CGPoint(x: xOffset, y: 0.6)
        // Wrist is at `angle` from the shoulder-elbow axis.
        // The shoulder->elbow vector points downward (angle = pi/2 from +x axis).
        // We rotate the downward unit vector by `angleRad` around the elbow.
        let wristPos = CGPoint(
            x: xOffset + sin(angleRad),
            y: 0.5 - cos(angleRad)
        )

        let shoulder = Joint(name: .leftShoulder, position: shoulderPos, confidence: confidence)
        let elbow    = Joint(name: .leftElbow,    position: elbowPos,    confidence: confidence)
        let wrist    = Joint(name: .leftWrist,    position: wristPos,    confidence: confidence)
        return (shoulder, elbow, wrist)
    }

    let left  = joints(angle: leftAngle,  xOffset: 0.35)
    let right = joints(angle: rightAngle, xOffset: 0.65)

    // Build the full joint dictionary; unneeded joints get zero confidence.
    var dict: [JointName: Joint] = [:]
    for name in JointName.allCases {
        dict[name] = Joint(name: name, position: .zero, confidence: 0)
    }
    dict[.leftShoulder]  = Joint(name: .leftShoulder,  position: left.shoulder.position,  confidence: confidence)
    dict[.leftElbow]     = Joint(name: .leftElbow,     position: left.elbow.position,     confidence: confidence)
    dict[.leftWrist]     = Joint(name: .leftWrist,     position: left.wrist.position,     confidence: confidence)
    dict[.rightShoulder] = Joint(name: .rightShoulder, position: right.shoulder.position, confidence: confidence)
    dict[.rightElbow]    = Joint(name: .rightElbow,    position: right.elbow.position,    confidence: confidence)
    dict[.rightWrist]    = Joint(name: .rightWrist,    position: right.wrist.position,    confidence: confidence)

    return BodyPose(joints: dict, timestamp: timestamp)
}

/// Feeds `count` identical frames with the given angle into `detector`.
private func feed(
    _ detector: PushUpDetector,
    angle: Double,
    frames: Int,
    timestamp: Double = 0
) {
    for i in 0..<frames {
        detector.process(makePose(leftAngle: angle, rightAngle: angle, timestamp: timestamp + Double(i)))
    }
}

/// Feeds `count` nil frames (no pose detected) into `detector`.
private func feedNil(_ detector: PushUpDetector, frames: Int) {
    for _ in 0..<frames {
        detector.process(nil)
    }
}

// MARK: - PushUpDetectorTests

@Suite("PushUpDetector")
struct PushUpDetectorTests {

    // MARK: Angle Calculation

    @Suite("Elbow angle calculation")
    struct AngleCalculation {

        @Test("Straight arm returns ~180 degrees")
        func straightArm() throws {
            let detector = PushUpDetector()
            // Shoulder above elbow, wrist below elbow (all collinear).
            let shoulder = Joint(name: .leftShoulder, position: CGPoint(x: 0.5, y: 0.8), confidence: 0.9)
            let elbow    = Joint(name: .leftElbow,    position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            let wrist    = Joint(name: .leftWrist,    position: CGPoint(x: 0.5, y: 0.2), confidence: 0.9)
            let angle = try #require(detector.elbowAngle(shoulder: shoulder, elbow: elbow, wrist: wrist))
            #expect(abs(angle - 180.0) < 0.5, "Expected ~180°, got \(angle)°")
        }

        @Test("Right-angle arm returns ~90 degrees")
        func rightAngle() throws {
            let detector = PushUpDetector()
            // Shoulder above elbow, wrist to the right of elbow.
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
            let angle = detector.elbowAngle(shoulder: shoulder, elbow: elbow, wrist: wrist)
            #expect(angle == nil)
        }

        @Test("Returns nil when a joint is nil")
        func nilJoint() {
            let detector = PushUpDetector()
            let elbow = Joint(name: .leftElbow, position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            let wrist = Joint(name: .leftWrist, position: CGPoint(x: 0.5, y: 0.2), confidence: 0.9)
            let angle = detector.elbowAngle(shoulder: nil, elbow: elbow, wrist: wrist)
            #expect(angle == nil)
        }

        @Test("angleBetween returns nil for degenerate zero-length vector")
        func degenerateVector() {
            let detector = PushUpDetector()
            let p = CGPoint(x: 0.5, y: 0.5)
            // vertex == a: zero-length vector
            let angle = detector.angleBetween(a: p, vertex: p, b: CGPoint(x: 0.5, y: 0.2))
            #expect(angle == nil)
        }

        @Test("Averaged angle uses both sides when both are detected")
        func averagesBothSides() throws {
            let detector = PushUpDetector()
            // Left side: 90°, right side: 180° -> average should be 135°
            let pose = makePose(leftAngle: 90, rightAngle: 180)
            let angle = try #require(detector.computeElbowAngle(from: pose))
            #expect(abs(angle - 135.0) < 1.0, "Expected ~135°, got \(angle)°")
        }

        @Test("Uses only left side when right side is undetected")
        func usesLeftWhenRightMissing() throws {
            let detector = PushUpDetector()
            var dict: [JointName: Joint] = [:]
            for name in JointName.allCases {
                dict[name] = Joint(name: name, position: .zero, confidence: 0)
            }
            // Only populate left arm joints.
            let shoulder = Joint(name: .leftShoulder, position: CGPoint(x: 0.5, y: 0.8), confidence: 0.9)
            let elbow    = Joint(name: .leftElbow,    position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
            let wrist    = Joint(name: .leftWrist,    position: CGPoint(x: 0.5, y: 0.2), confidence: 0.9)
            dict[.leftShoulder] = shoulder
            dict[.leftElbow]    = elbow
            dict[.leftWrist]    = wrist
            let pose = BodyPose(joints: dict, timestamp: 0)
            let angle = try #require(detector.computeElbowAngle(from: pose))
            #expect(abs(angle - 180.0) < 0.5)
        }

        @Test("Returns nil when pose is nil")
        func nilPose() {
            let detector = PushUpDetector()
            let angle = detector.computeElbowAngle(from: nil)
            #expect(angle == nil)
        }
    }

    // MARK: State Machine Integration

    @Suite("State machine integration")
    struct StateMachineIntegration {

        @Test("No push-up counted without DOWN phase")
        func noPushUpWithoutDown() {
            let detector = PushUpDetector()
            // Feed only UP-range angles; never go below the DOWN threshold.
            feed(detector, angle: 170, frames: 10)
            #expect(detector.pushUpCount == 0)
            #expect(detector.currentPhase == .idle)
        }

        @Test("No push-up counted for partial cycle (DOWN only, no UP)")
        func halfPushUpNotCounted() {
            let config = PushUpStateMachine.Configuration(
                downAngleThreshold: 90,
                upAngleThreshold: 160,
                hysteresisFrameCount: 3,
                cooldownFrameCount: 5
            )
            let detector = PushUpDetector(configuration: config)
            // Go down (3 frames to satisfy hysteresis).
            feed(detector, angle: 70, frames: 3)
            #expect(detector.currentPhase == .down)
            // Stay down; never come back up.
            feed(detector, angle: 70, frames: 5)
            #expect(detector.pushUpCount == 0)
        }

        @Test("One complete push-up is counted")
        func onePushUp() {
            let config = PushUpStateMachine.Configuration(
                downAngleThreshold: 90,
                upAngleThreshold: 160,
                hysteresisFrameCount: 3,
                cooldownFrameCount: 5
            )
            let detector = PushUpDetector(configuration: config)
            // DOWN phase.
            feed(detector, angle: 70, frames: 3)
            #expect(detector.currentPhase == .down)
            // UP phase.
            feed(detector, angle: 170, frames: 3)
            #expect(detector.pushUpCount == 1)
        }

        @Test("Multiple push-ups are counted correctly")
        func multiplePushUps() {
            let config = PushUpStateMachine.Configuration(
                downAngleThreshold: 90,
                upAngleThreshold: 160,
                hysteresisFrameCount: 3,
                cooldownFrameCount: 5
            )
            let detector = PushUpDetector(configuration: config)

            for _ in 0..<5 {
                // DOWN
                feed(detector, angle: 70, frames: 3)
                // UP
                feed(detector, angle: 170, frames: 3)
                // Wait out cooldown
                feed(detector, angle: 170, frames: 5)
            }
            #expect(detector.pushUpCount == 5)
        }

        @Test("Hysteresis prevents counting on brief angle dip")
        func hysteresisPreventsFalseCount() {
            let config = PushUpStateMachine.Configuration(
                downAngleThreshold: 90,
                upAngleThreshold: 160,
                hysteresisFrameCount: 3,
                cooldownFrameCount: 5
            )
            let detector = PushUpDetector(configuration: config)
            // Only 2 frames below DOWN threshold (less than hysteresisFrameCount=3).
            feed(detector, angle: 70, frames: 2)
            #expect(detector.currentPhase == .idle, "Should still be idle after only 2 frames")
            #expect(detector.pushUpCount == 0)
        }

        @Test("Cooldown prevents double-counting")
        func cooldownPreventsDuplicateCount() {
            let config = PushUpStateMachine.Configuration(
                downAngleThreshold: 90,
                upAngleThreshold: 160,
                hysteresisFrameCount: 3,
                cooldownFrameCount: 15
            )
            let detector = PushUpDetector(configuration: config)
            // Complete one push-up.
            feed(detector, angle: 70, frames: 3)
            feed(detector, angle: 170, frames: 3)
            #expect(detector.pushUpCount == 1)
            // Immediately try another DOWN->UP cycle during cooldown.
            feed(detector, angle: 70, frames: 3)
            feed(detector, angle: 170, frames: 3)
            // Still only 1 because we are in cooldown.
            #expect(detector.pushUpCount == 1)
        }

        @Test("Second push-up counted after cooldown expires")
        func secondPushUpAfterCooldown() {
            let config = PushUpStateMachine.Configuration(
                downAngleThreshold: 90,
                upAngleThreshold: 160,
                hysteresisFrameCount: 3,
                cooldownFrameCount: 5
            )
            let detector = PushUpDetector(configuration: config)
            // First push-up.
            feed(detector, angle: 70, frames: 3)
            feed(detector, angle: 170, frames: 3)
            #expect(detector.pushUpCount == 1)
            // Wait out cooldown (5 frames).
            feed(detector, angle: 170, frames: 5)
            #expect(detector.currentPhase == .idle)
            // Second push-up.
            feed(detector, angle: 70, frames: 3)
            feed(detector, angle: 170, frames: 3)
            #expect(detector.pushUpCount == 2)
        }

        @Test("Nil pose frames do not advance hysteresis counter")
        func nilPoseDoesNotAdvanceHysteresis() {
            let config = PushUpStateMachine.Configuration(
                downAngleThreshold: 90,
                upAngleThreshold: 160,
                hysteresisFrameCount: 3,
                cooldownFrameCount: 5
            )
            let detector = PushUpDetector(configuration: config)
            // 2 frames below threshold, then a nil frame, then 1 more below.
            feed(detector, angle: 70, frames: 2)
            feedNil(detector, frames: 1)
            feed(detector, angle: 70, frames: 1)
            // Total below-threshold frames = 3, but the nil reset the counter.
            // After nil: counter reset to 0. Then 1 more frame -> counter = 1.
            // So we should still be in idle.
            #expect(detector.currentPhase == .idle)
        }

        @Test("Slow push-up (many frames per phase) is counted correctly")
        func slowPushUp() {
            let config = PushUpStateMachine.Configuration(
                downAngleThreshold: 90,
                upAngleThreshold: 160,
                hysteresisFrameCount: 3,
                cooldownFrameCount: 5
            )
            let detector = PushUpDetector(configuration: config)
            // Slow descent: 30 frames at low angle.
            feed(detector, angle: 60, frames: 30)
            #expect(detector.currentPhase == .down)
            // Slow ascent: 30 frames at high angle.
            feed(detector, angle: 170, frames: 30)
            #expect(detector.pushUpCount == 1)
        }

        @Test("Fast push-ups (minimum frames) are counted correctly")
        func fastPushUps() {
            let config = PushUpStateMachine.Configuration(
                downAngleThreshold: 90,
                upAngleThreshold: 160,
                hysteresisFrameCount: 3,
                cooldownFrameCount: 5
            )
            let detector = PushUpDetector(configuration: config)
            // 3 push-ups with minimum frames per phase.
            for _ in 0..<3 {
                feed(detector, angle: 70, frames: 3)
                feed(detector, angle: 170, frames: 3)
                feed(detector, angle: 170, frames: 5) // cooldown
            }
            #expect(detector.pushUpCount == 3)
        }

        @Test("Noisy angle oscillation around threshold does not cause false count")
        func noisyAngleOscillation() {
            let config = PushUpStateMachine.Configuration(
                downAngleThreshold: 90,
                upAngleThreshold: 160,
                hysteresisFrameCount: 3,
                cooldownFrameCount: 5
            )
            let detector = PushUpDetector(configuration: config)
            // Oscillate around the DOWN threshold (89/91) without holding for 3 frames.
            for _ in 0..<20 {
                feed(detector, angle: 89, frames: 1)
                feed(detector, angle: 91, frames: 1)
            }
            #expect(detector.pushUpCount == 0)
            #expect(detector.currentPhase == .idle)
        }

        @Test("Reset clears count and returns to idle")
        func resetClearsState() {
            let config = PushUpStateMachine.Configuration(
                downAngleThreshold: 90,
                upAngleThreshold: 160,
                hysteresisFrameCount: 3,
                cooldownFrameCount: 5
            )
            let detector = PushUpDetector(configuration: config)
            feed(detector, angle: 70, frames: 3)
            feed(detector, angle: 170, frames: 3)
            #expect(detector.pushUpCount == 1)
            detector.reset()
            #expect(detector.pushUpCount == 0)
            #expect(detector.currentPhase == .idle)
            #expect(detector.currentElbowAngle == nil)
        }
    }

    // MARK: Delegate

    @Suite("Delegate callbacks")
    struct DelegateCallbacks {

        /// A simple delegate that records received events.
        final class RecordingDelegate: PushUpDetectorDelegate, @unchecked Sendable {
            var events: [PushUpEvent] = []
            func pushUpDetector(_ detector: PushUpDetector, didCount event: PushUpEvent) {
                events.append(event)
            }
        }

        @Test("Delegate receives event for each push-up")
        func delegateReceivesEvents() {
            let config = PushUpStateMachine.Configuration(
                downAngleThreshold: 90,
                upAngleThreshold: 160,
                hysteresisFrameCount: 3,
                cooldownFrameCount: 5
            )
            let detector = PushUpDetector(configuration: config)
            let delegate = RecordingDelegate()
            detector.delegate = delegate

            // Three push-ups.
            for _ in 0..<3 {
                feed(detector, angle: 70, frames: 3)
                feed(detector, angle: 170, frames: 3)
                feed(detector, angle: 170, frames: 5) // cooldown
            }

            #expect(delegate.events.count == 3)
            #expect(delegate.events[0].count == 1)
            #expect(delegate.events[1].count == 2)
            #expect(delegate.events[2].count == 3)
        }

        @Test("Delegate event carries correct timestamp")
        func delegateEventTimestamp() {
            let config = PushUpStateMachine.Configuration(
                downAngleThreshold: 90,
                upAngleThreshold: 160,
                hysteresisFrameCount: 3,
                cooldownFrameCount: 5
            )
            let detector = PushUpDetector(configuration: config)
            let delegate = RecordingDelegate()
            detector.delegate = delegate

            // Feed DOWN frames starting at t=0.
            for i in 0..<3 {
                detector.process(makePose(leftAngle: 70, rightAngle: 70, timestamp: Double(i)))
            }
            // Feed UP frames starting at t=10.
            for i in 0..<3 {
                detector.process(makePose(leftAngle: 170, rightAngle: 170, timestamp: 10.0 + Double(i)))
            }

            #expect(delegate.events.count == 1)
            // The event timestamp should be the frame that triggered the count (t=12).
            #expect(delegate.events[0].timestamp == 12.0)
        }

        @Test("No delegate event when no push-up is counted")
        func noDelegateEventWithoutPushUp() {
            let detector = PushUpDetector()
            let delegate = RecordingDelegate()
            detector.delegate = delegate
            feed(detector, angle: 170, frames: 30)
            #expect(delegate.events.isEmpty)
        }
    }

    // MARK: PushUpStateMachine direct tests

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
            #expect(sm.phase == .idle) // Not yet
            sm.update(angle: 80)
            #expect(sm.phase == .down)
        }

        @Test("Resets pending counter when condition breaks")
        func pendingCounterReset() {
            let config = PushUpStateMachine.Configuration(hysteresisFrameCount: 3)
            let sm = PushUpStateMachine(configuration: config)
            sm.update(angle: 80)
            sm.update(angle: 80)
            sm.update(angle: 100) // breaks the condition
            sm.update(angle: 80)
            sm.update(angle: 80)
            // Only 2 consecutive frames below threshold after the break.
            #expect(sm.phase == .idle)
        }

        @Test("Cooldown phase counts down to idle")
        func cooldownCountsDown() {
            let config = PushUpStateMachine.Configuration(
                hysteresisFrameCount: 1,
                cooldownFrameCount: 3
            )
            let sm = PushUpStateMachine(configuration: config)
            sm.update(angle: 80)  // -> down
            sm.update(angle: 170) // -> up (count=1)
            sm.update(angle: 170) // -> cooldown (triggered by .up handler)
            #expect(sm.phase == .cooldown)
            sm.update(angle: 170) // cooldown frame 1
            sm.update(angle: 170) // cooldown frame 2
            sm.update(angle: 170) // cooldown frame 3 -> idle
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
            let r2 = sm.update(angle: 170)  // down -> up (count!)
            let r3 = sm.update(angle: 170)  // up -> cooldown
            let r4 = sm.update(angle: 170)  // cooldown -> idle
            #expect(r1 == false)
            #expect(r2 == true)
            #expect(r3 == false)
            #expect(r4 == false)
        }
    }
}
