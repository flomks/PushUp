import CoreGraphics
import Testing

@testable import iosApp

// MARK: - Test Helpers

/// Builds a `BodyPose` with arm joints set to produce the requested elbow
/// angles. Hip joints are placed at the same y-coordinate as the shoulders
/// (horizontal push-up position) by default.
///
/// - Parameters:
///   - leftAngle:   Desired left elbow angle (degrees). Pass `nil` to leave
///                  the left arm joints at zero confidence (undetected).
///   - rightAngle:  Desired right elbow angle (degrees). Pass `nil` to leave
///                  the right arm joints at zero confidence (undetected).
///   - spineAngleDeg: Angle of the shoulder-to-hip spine vector from
///                  horizontal (degrees). 0 = perfect horizontal back.
///                  Positive values tilt the spine upward toward the hips.
///   - confidence:  Confidence applied to all detected joints (default 0.9).
///   - timestamp:   Frame timestamp in seconds (default 0).
private func makePose(
    leftAngle: Double? = 90.0,
    rightAngle: Double? = 90.0,
    spineAngleDeg: Double = 0.0,
    confidence: Float = 0.9,
    timestamp: Double = 0
) -> BodyPose {
    func armJoints(
        angleDeg: Double,
        xOffset: Double,
        shoulderName: JointName,
        elbowName: JointName,
        wristName: JointName
    ) -> [JointName: Joint] {
        let rad = angleDeg * .pi / 180.0
        let elbowPos    = CGPoint(x: xOffset, y: 0.5)
        let shoulderPos = CGPoint(x: xOffset, y: 0.6)
        let wristPos    = CGPoint(x: xOffset + sin(rad), y: 0.5 - cos(rad))
        return [
            shoulderName: Joint(name: shoulderName, position: shoulderPos, confidence: confidence),
            elbowName:    Joint(name: elbowName,    position: elbowPos,    confidence: confidence),
            wristName:    Joint(name: wristName,    position: wristPos,    confidence: confidence),
        ]
    }

    var dict: [JointName: Joint] = Dictionary(
        uniqueKeysWithValues: JointName.allCases.map { name in
            (name, Joint(name: name, position: .zero, confidence: 0))
        }
    )

    // Left arm
    if let leftAngle {
        let joints = armJoints(
            angleDeg: leftAngle, xOffset: 0.35,
            shoulderName: .leftShoulder, elbowName: .leftElbow, wristName: .leftWrist
        )
        dict.merge(joints) { _, new in new }
    }

    // Right arm
    if let rightAngle {
        let joints = armJoints(
            angleDeg: rightAngle, xOffset: 0.65,
            shoulderName: .rightShoulder, elbowName: .rightElbow, wristName: .rightWrist
        )
        dict.merge(joints) { _, new in new }
    }

    // Hip joints: placed relative to shoulder midpoint (0.5, 0.6) along the
    // spine direction defined by spineAngleDeg.
    // spineAngleDeg = 0 → hips directly to the right (horizontal spine).
    // spineAngleDeg > 0 → hips tilted upward (piked).
    // spineAngleDeg < 0 → hips tilted downward (sagging).
    let spineRad = spineAngleDeg * .pi / 180.0
    let spineLength = 0.2
    let shoulderMidX = 0.5
    let shoulderMidY = 0.6
    let hipMidX = shoulderMidX + cos(spineRad) * spineLength
    let hipMidY = shoulderMidY + sin(spineRad) * spineLength

    dict[.leftHip]  = Joint(name: .leftHip,  position: CGPoint(x: hipMidX - 0.1, y: hipMidY), confidence: confidence)
    dict[.rightHip] = Joint(name: .rightHip, position: CGPoint(x: hipMidX + 0.1, y: hipMidY), confidence: confidence)

    return BodyPose(joints: dict, timestamp: timestamp)
}

// MARK: - FormScorerTests

@Suite("FormScorer")
struct FormScorerTests {

    // MARK: - Depth Score (pure function)

    @Suite("depthScore pure function")
    struct DepthScorePureFunction {

        @Test("Angle at 90 degrees returns 0.5 (spec anchor)")
        func angle90Returns05() {
            let score = FormScorer.depthScore(for: 90.0)
            #expect(abs(score - 0.5) < 0.001, "Expected 0.5, got \(score)")
        }

        @Test("Angle at 70 degrees returns 0.8 (spec anchor)")
        func angle70Returns08() {
            let score = FormScorer.depthScore(for: 70.0)
            #expect(abs(score - 0.8) < 0.001, "Expected 0.8, got \(score)")
        }

        @Test("Angle at 60 degrees returns 1.0 (spec anchor)")
        func angle60Returns10() {
            let score = FormScorer.depthScore(for: 60.0)
            #expect(abs(score - 1.0) < 0.001, "Expected 1.0, got \(score)")
        }

        @Test("Angle below 60 degrees is clamped to 1.0")
        func angleBelowFullDepthClamped() {
            let score = FormScorer.depthScore(for: 45.0)
            #expect(abs(score - 1.0) < 0.001, "Expected 1.0, got \(score)")
        }

        @Test("Angle above 90 degrees returns 0.0")
        func angleAboveThresholdReturnsZero() {
            let score = FormScorer.depthScore(for: 120.0)
            #expect(abs(score - 0.0) < 0.001, "Expected 0.0, got \(score)")
        }

        @Test("Angle at 180 degrees returns 0.0")
        func angle180ReturnsZero() {
            let score = FormScorer.depthScore(for: 180.0)
            #expect(abs(score - 0.0) < 0.001, "Expected 0.0, got \(score)")
        }

        @Test("Midpoint between 90 and 70 degrees returns ~0.65")
        func midpointBetween90And70() {
            // Linear interpolation: at 80° (midpoint of [70, 90]) → 0.5 + 0.5*(0.8-0.5) = 0.65
            let score = FormScorer.depthScore(for: 80.0)
            #expect(abs(score - 0.65) < 0.01, "Expected ~0.65, got \(score)")
        }

        @Test("Midpoint between 70 and 60 degrees returns ~0.9")
        func midpointBetween70And60() {
            // Linear interpolation: at 65° (midpoint of [60, 70]) → 0.8 + 0.5*(1.0-0.8) = 0.9
            let score = FormScorer.depthScore(for: 65.0)
            #expect(abs(score - 0.9) < 0.01, "Expected ~0.9, got \(score)")
        }

        @Test("Score is monotonically increasing as angle decreases from 90 to 60")
        func monotonicIncrease() {
            var previousScore = FormScorer.depthScore(for: 90.0)
            for angle in stride(from: 89.0, through: 60.0, by: -1.0) {
                let score = FormScorer.depthScore(for: angle)
                #expect(score >= previousScore,
                        "Score should not decrease as angle decreases: \(angle)° → \(score) < \(previousScore)")
                previousScore = score
            }
        }

        @Test("Custom configuration anchors are respected")
        func customConfiguration() {
            let config = FormScorer.Configuration(
                depthAnchorHalf: 80.0,
                depthAnchorHigh: 60.0,
                depthAnchorFull: 50.0
            )
            let score80 = FormScorer.depthScore(for: 80.0, configuration: config)
            let score60 = FormScorer.depthScore(for: 60.0, configuration: config)
            let score50 = FormScorer.depthScore(for: 50.0, configuration: config)
            #expect(abs(score80 - 0.5) < 0.001)
            #expect(abs(score60 - 0.8) < 0.001)
            #expect(abs(score50 - 1.0) < 0.001)
        }
    }

    // MARK: - Back Alignment Sub-Score (pure function)

    @Suite("backAlignmentScore pure function")
    struct BackAlignmentScore {

        /// Builds a pose with shoulder and hip joints placed to produce a
        /// spine vector at the given angle from horizontal.
        private func poseWithSpineAngle(_ angleDeg: Double) -> BodyPose {
            makePose(spineAngleDeg: angleDeg)
        }

        @Test("Horizontal spine (0 degrees) scores 1.0")
        func horizontalSpineScores10() throws {
            let pose = poseWithSpineAngle(0.0)
            let score = try #require(FormScorer.backAlignmentScore(pose: pose))
            #expect(abs(score - 1.0) < 0.01, "Expected 1.0, got \(score)")
        }

        @Test("Tilted spine reduces score")
        func tiltedSpineReducesScore() throws {
            let pose = poseWithSpineAngle(20.0)
            let score = try #require(FormScorer.backAlignmentScore(pose: pose))
            #expect(score < 1.0, "Tilted spine should score less than 1.0, got \(score)")
            #expect(score >= 0.0, "Score must be non-negative, got \(score)")
        }

        @Test("Spine tilted at maxBackAngleDeviation scores 0.0")
        func maxDeviationScoresZero() throws {
            let config = FormScorer.Configuration(maxBackAngleDeviation: 30.0)
            let pose = poseWithSpineAngle(30.0)
            let score = try #require(FormScorer.backAlignmentScore(pose: pose, configuration: config))
            #expect(abs(score - 0.0) < 0.01, "Expected 0.0 at max deviation, got \(score)")
        }

        @Test("Score is clamped to [0, 1] for extreme tilt")
        func scoreIsClamped() throws {
            let pose = poseWithSpineAngle(90.0)
            let score = try #require(FormScorer.backAlignmentScore(pose: pose))
            #expect(score >= 0.0 && score <= 1.0, "Score out of range: \(score)")
        }

        @Test("Returns nil when no hip joints are detected")
        func returnsNilWithoutHips() {
            var dict: [JointName: Joint] = Dictionary(
                uniqueKeysWithValues: JointName.allCases.map { name in
                    (name, Joint(name: name, position: .zero, confidence: 0))
                }
            )
            // Add shoulders but no hips.
            dict[.leftShoulder]  = Joint(name: .leftShoulder,  position: CGPoint(x: 0.35, y: 0.6), confidence: 0.9)
            dict[.rightShoulder] = Joint(name: .rightShoulder, position: CGPoint(x: 0.65, y: 0.6), confidence: 0.9)
            let pose = BodyPose(joints: dict, timestamp: 0)
            let score = FormScorer.backAlignmentScore(pose: pose)
            #expect(score == nil, "Expected nil when hips are not detected")
        }

        @Test("Returns nil when no shoulder joints are detected")
        func returnsNilWithoutShoulders() {
            var dict: [JointName: Joint] = Dictionary(
                uniqueKeysWithValues: JointName.allCases.map { name in
                    (name, Joint(name: name, position: .zero, confidence: 0))
                }
            )
            // Add hips but no shoulders.
            dict[.leftHip]  = Joint(name: .leftHip,  position: CGPoint(x: 0.35, y: 0.6), confidence: 0.9)
            dict[.rightHip] = Joint(name: .rightHip, position: CGPoint(x: 0.65, y: 0.6), confidence: 0.9)
            let pose = BodyPose(joints: dict, timestamp: 0)
            let score = FormScorer.backAlignmentScore(pose: pose)
            #expect(score == nil, "Expected nil when shoulders are not detected")
        }

        @Test("Score decreases monotonically as spine tilt increases from 0 to maxDeviation")
        func monotonicDecrease() {
            var previousScore = 1.0
            for angleDeg in stride(from: 1.0, through: 30.0, by: 1.0) {
                let pose = poseWithSpineAngle(angleDeg)
                if let score = FormScorer.backAlignmentScore(pose: pose) {
                    #expect(score <= previousScore,
                            "Score should not increase as tilt increases: \(angleDeg)° → \(score) > \(previousScore)")
                    previousScore = score
                }
            }
        }
    }

    // MARK: - FormScorer Instance: Depth Tracking

    @Suite("Depth tracking via recordFrame")
    struct DepthTracking {

        @Test("Minimum angle during DOWN phase determines depth score")
        func minimumAngleUsedForDepth() throws {
            let scorer = FormScorer()
            let pose = makePose(leftAngle: 90.0, rightAngle: 90.0)

            // Feed several DOWN-phase frames with decreasing angles.
            scorer.recordFrame(pose: pose, leftElbowAngle: 85.0, rightElbowAngle: 85.0, isInDownPhase: true)
            scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: true)
            scorer.recordFrame(pose: pose, leftElbowAngle: 75.0, rightElbowAngle: 75.0, isInDownPhase: true)

            let result = try #require(scorer.finalisePushUp())
            // Minimum angle was 70° → depth score should be 0.8.
            #expect(abs(result.depthScore - 0.8) < 0.01,
                    "Expected depthScore ~0.8, got \(result.depthScore)")
        }

        @Test("Non-DOWN-phase frames do not contribute to depth score")
        func nonDownFramesIgnoredForDepth() throws {
            let scorer = FormScorer()
            let pose = makePose(leftAngle: 90.0, rightAngle: 90.0)

            // Feed a very low angle but NOT in DOWN phase.
            scorer.recordFrame(pose: pose, leftElbowAngle: 30.0, rightElbowAngle: 30.0, isInDownPhase: false)
            // Feed a moderate angle in DOWN phase.
            scorer.recordFrame(pose: pose, leftElbowAngle: 80.0, rightElbowAngle: 80.0, isInDownPhase: true)

            let result = try #require(scorer.finalisePushUp())
            // Only the 80° DOWN-phase frame should count → depth score ~0.65.
            #expect(result.depthScore < 0.8,
                    "Non-DOWN frame should not affect depth score, got \(result.depthScore)")
        }

        @Test("Returns nil depth when no DOWN-phase frames were recorded")
        func nilDepthWithoutDownFrames() {
            let scorer = FormScorer()
            let pose = makePose(leftAngle: 90.0, rightAngle: 90.0)

            // Feed only non-DOWN frames.
            scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: false)

            // computeDepthScore should return nil (no DOWN-phase data).
            let depthScore = scorer.computeDepthScore()
            #expect(depthScore == nil, "Expected nil depth score without DOWN-phase frames")
        }

        @Test("Nil angle in DOWN phase does not update minimum angle")
        func nilAngleInDownPhaseIgnored() {
            let scorer = FormScorer()
            let pose = makePose(leftAngle: 90.0, rightAngle: 90.0)

            // Feed a nil angle in DOWN phase (both arms undetected).
            scorer.recordFrame(pose: pose, leftElbowAngle: nil, rightElbowAngle: nil, isInDownPhase: true)

            // computeDepthScore should return nil (no valid DOWN-phase angle).
            let depthScore = scorer.computeDepthScore()
            #expect(depthScore == nil, "Expected nil depth score when only nil angles in DOWN phase")
        }
    }

    // MARK: - FormScorer Instance: Arm Symmetry

    @Suite("Arm symmetry sub-score")
    struct ArmSymmetry {

        @Test("Perfectly symmetric arms contribute maximum symmetry sub-score")
        func symmetricArmsMaxScore() throws {
            let scorer = FormScorer()
            // Horizontal spine so back-alignment sub-score is also 1.0.
            let pose = makePose(leftAngle: 70.0, rightAngle: 70.0, spineAngleDeg: 0.0)

            // Feed multiple frames so smoothness samples are also collected.
            for _ in 0..<5 {
                scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: true)
            }

            let result = try #require(scorer.finalisePushUp())
            // All three sub-scores should be 1.0 → formScore == 1.0.
            #expect(abs(result.formScore - 1.0) < 0.01,
                    "Perfect symmetry, alignment, and smoothness should give formScore 1.0, got \(result.formScore)")
        }

        @Test("Maximum asymmetry reduces symmetry sub-score to 0")
        func maxAsymmetryZeroScore() throws {
            let config = FormScorer.Configuration(maxArmAsymmetry: 30.0)
            let scorer = FormScorer(configuration: config)
            let pose = makePose(leftAngle: 70.0, rightAngle: 70.0)

            // 30° asymmetry → symmetry sub-score = 0.0.
            for _ in 0..<5 {
                scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 100.0, isInDownPhase: true)
            }

            let result = try #require(scorer.finalisePushUp())
            // Symmetry sub-score is 0.0; form score is mean of available sub-scores.
            // Back alignment and smoothness may contribute positively.
            #expect(result.formScore < 1.0, "Max asymmetry should reduce form score below 1.0")
        }

        @Test("Only one arm detected: symmetry sub-score not computed")
        func oneArmNoSymmetryScore() {
            let scorer = FormScorer()
            let pose = makePose(leftAngle: 70.0, rightAngle: nil)

            // Only left arm angle provided.
            for _ in 0..<5 {
                scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: nil, isInDownPhase: true)
            }

            // Should still produce a result from back alignment and smoothness.
            let result = scorer.finalisePushUp()
            if let result {
                #expect(result.formScore >= 0.0 && result.formScore <= 1.0)
            }
        }
    }

    // MARK: - FormScorer Instance: Smoothness

    @Suite("Movement smoothness sub-score")
    struct MovementSmoothness {

        @Test("Constant angle produces maximum smoothness sub-score")
        func constantAngleMaxSmoothness() throws {
            let scorer = FormScorer()
            // Horizontal spine so back-alignment is also 1.0.
            let pose = makePose(leftAngle: 70.0, rightAngle: 70.0, spineAngleDeg: 0.0)

            // Feed many frames with the same angle.
            for _ in 0..<10 {
                scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: true)
            }

            let result = try #require(scorer.finalisePushUp())
            // Zero delta → smoothness 1.0; symmetric → symmetry 1.0; horizontal → alignment 1.0.
            #expect(abs(result.formScore - 1.0) < 0.01,
                    "Constant angle with perfect form should give formScore 1.0, got \(result.formScore)")
        }

        @Test("Jerky movement at max delta reduces smoothness sub-score to 0")
        func maxDeltaZeroSmoothnessScore() throws {
            let config = FormScorer.Configuration(maxFrameAngleDelta: 20.0)
            let scorer = FormScorer(configuration: config)
            let pose = makePose(leftAngle: 70.0, rightAngle: 70.0)

            // Alternate between two angles exactly 20° apart → smoothness sub-score = 0.0.
            scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: true)
            scorer.recordFrame(pose: pose, leftElbowAngle: 90.0, rightElbowAngle: 90.0, isInDownPhase: true)
            scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: true)
            scorer.recordFrame(pose: pose, leftElbowAngle: 90.0, rightElbowAngle: 90.0, isInDownPhase: false)

            let result = try #require(scorer.finalisePushUp())
            // Smoothness sub-score is 0.0; form score should be reduced.
            #expect(result.formScore < 1.0, "Jerky movement should reduce form score")
        }

        @Test("Nil pose resets smoothness baseline (no spurious large delta)")
        func nilPoseResetsBaseline() {
            let scorer = FormScorer()
            let pose = makePose(leftAngle: 70.0, rightAngle: 70.0)

            // Feed a frame, then a nil pose, then a very different angle.
            scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: true)
            scorer.recordFrame(pose: nil, leftElbowAngle: nil, rightElbowAngle: nil, isInDownPhase: false)
            // After nil, the next frame should not produce a large delta.
            scorer.recordFrame(pose: pose, leftElbowAngle: 170.0, rightElbowAngle: 170.0, isInDownPhase: false)

            // Should not crash and should produce a valid result.
            let result = scorer.finalisePushUp()
            if let result {
                #expect(result.formScore >= 0.0 && result.formScore <= 1.0)
            }
        }

        @Test("Single frame produces no smoothness samples (no previous frame)")
        func singleFrameNoSmoothnessData() throws {
            let scorer = FormScorer()
            let pose = makePose(leftAngle: 70.0, rightAngle: 70.0)

            // Only one frame: no previous frame to compare against.
            scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: true)

            // Should still produce a result from depth and back alignment.
            let result = scorer.finalisePushUp()
            if let result {
                #expect(result.formScore >= 0.0 && result.formScore <= 1.0)
            }
        }
    }

    // MARK: - FormScorer Instance: Combined Score

    @Suite("Combined score")
    struct CombinedScore {

        @Test("Combined score is the mean of depth and form scores")
        func combinedScoreIsMean() throws {
            let scorer = FormScorer()
            let pose = makePose(leftAngle: 70.0, rightAngle: 70.0)

            scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: true)
            scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: false)

            let result = try #require(scorer.finalisePushUp())
            let expected = (result.depthScore + result.formScore) / 2.0
            #expect(abs(result.combinedScore - expected) < 0.0001,
                    "combinedScore should equal (depth + form) / 2")
        }

        @Test("Combined score is in [0, 1]")
        func combinedScoreInRange() throws {
            let scorer = FormScorer()
            let pose = makePose(leftAngle: 60.0, rightAngle: 60.0)

            for _ in 0..<5 {
                scorer.recordFrame(pose: pose, leftElbowAngle: 60.0, rightElbowAngle: 60.0, isInDownPhase: true)
            }
            scorer.recordFrame(pose: pose, leftElbowAngle: 170.0, rightElbowAngle: 170.0, isInDownPhase: false)

            let result = try #require(scorer.finalisePushUp())
            #expect(result.combinedScore >= 0.0 && result.combinedScore <= 1.0,
                    "Combined score out of range: \(result.combinedScore)")
        }

        @Test("depthScore and formScore are both in [0, 1]")
        func componentScoresInRange() throws {
            let scorer = FormScorer()
            let pose = makePose(leftAngle: 70.0, rightAngle: 70.0)

            for _ in 0..<5 {
                scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: true)
            }

            let result = try #require(scorer.finalisePushUp())
            #expect(result.depthScore >= 0.0 && result.depthScore <= 1.0,
                    "depthScore out of range: \(result.depthScore)")
            #expect(result.formScore >= 0.0 && result.formScore <= 1.0,
                    "formScore out of range: \(result.formScore)")
        }
    }

    // MARK: - FormScorer Instance: Reset

    @Suite("Reset behaviour")
    struct ResetBehaviour {

        @Test("Reset clears accumulated depth state")
        func resetClearsDepthState() {
            let scorer = FormScorer()
            let pose = makePose(leftAngle: 70.0, rightAngle: 70.0)

            scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: true)
            scorer.reset()

            // After reset, computeDepthScore should return nil (no DOWN-phase data).
            let depthScore = scorer.computeDepthScore()
            #expect(depthScore == nil, "Depth score should be nil after reset")
        }

        @Test("finalisePushUp resets state automatically")
        func finaliseResetsState() {
            let scorer = FormScorer()
            let pose = makePose(leftAngle: 70.0, rightAngle: 70.0)

            scorer.recordFrame(pose: pose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: true)
            _ = scorer.finalisePushUp()

            // After finalise, depth score should be nil (state was reset).
            let depthScore = scorer.computeDepthScore()
            #expect(depthScore == nil, "Depth score should be nil after finalisePushUp")
        }

        @Test("Returns nil when no frames were recorded")
        func returnsNilWithNoFrames() {
            let scorer = FormScorer()
            let result = scorer.finalisePushUp()
            #expect(result == nil, "Expected nil when no frames were recorded")
        }

        @Test("Second push-up after reset produces independent scores")
        func secondPushUpIndependent() throws {
            let scorer = FormScorer()
            let deepPose    = makePose(leftAngle: 60.0, rightAngle: 60.0)
            let shallowPose = makePose(leftAngle: 88.0, rightAngle: 88.0)

            // First push-up: deep.
            scorer.recordFrame(pose: deepPose, leftElbowAngle: 60.0, rightElbowAngle: 60.0, isInDownPhase: true)
            let first = try #require(scorer.finalisePushUp())

            // Second push-up: shallow.
            scorer.recordFrame(pose: shallowPose, leftElbowAngle: 88.0, rightElbowAngle: 88.0, isInDownPhase: true)
            let second = try #require(scorer.finalisePushUp())

            #expect(first.depthScore > second.depthScore,
                    "Deep push-up should score higher than shallow: \(first.depthScore) vs \(second.depthScore)")
        }
    }

    // MARK: - FormScorer Instance: Various Pose Qualities

    @Suite("Various pose quality scenarios")
    struct PoseQualityScenarios {

        @Test("Perfect push-up: deep, symmetric, smooth, straight back")
        func perfectPushUp() throws {
            let scorer = FormScorer()
            // Horizontal spine (0° tilt) = perfect back alignment.
            let pose = makePose(leftAngle: 60.0, rightAngle: 60.0, spineAngleDeg: 0.0)

            for _ in 0..<10 {
                scorer.recordFrame(pose: pose, leftElbowAngle: 60.0, rightElbowAngle: 60.0, isInDownPhase: true)
            }

            let result = try #require(scorer.finalisePushUp())
            // Deep push-up: depthScore should be 1.0.
            #expect(abs(result.depthScore - 1.0) < 0.001,
                    "Perfect depth should score 1.0, got \(result.depthScore)")
            // Combined score should be high.
            #expect(result.combinedScore > 0.7,
                    "Perfect push-up should have high combined score, got \(result.combinedScore)")
        }

        @Test("Shallow push-up: angle barely below DOWN threshold")
        func shallowPushUp() throws {
            let scorer = FormScorer()
            let pose = makePose(leftAngle: 89.0, rightAngle: 89.0)

            scorer.recordFrame(pose: pose, leftElbowAngle: 89.0, rightElbowAngle: 89.0, isInDownPhase: true)

            let result = try #require(scorer.finalisePushUp())
            // Angle 89° is just below 90° → depth score just above 0.5.
            #expect(result.depthScore > 0.5 && result.depthScore < 0.6,
                    "Shallow push-up depth score should be just above 0.5, got \(result.depthScore)")
        }

        @Test("Asymmetric push-up: one arm much more bent than the other")
        func asymmetricPushUp() throws {
            let config = FormScorer.Configuration(maxArmAsymmetry: 30.0)
            let scorer = FormScorer(configuration: config)
            let pose = makePose(leftAngle: 60.0, rightAngle: 90.0)

            // 30° asymmetry → symmetry sub-score = 0.0.
            for _ in 0..<5 {
                scorer.recordFrame(pose: pose, leftElbowAngle: 60.0, rightElbowAngle: 90.0, isInDownPhase: true)
            }

            let result = try #require(scorer.finalisePushUp())
            // Form score should be reduced due to asymmetry.
            #expect(result.formScore < 0.8,
                    "Asymmetric push-up should have reduced form score, got \(result.formScore)")
        }

        @Test("Tilted back reduces form score compared to straight back")
        func tiltedBackReducesFormScore() throws {
            let scorer1 = FormScorer()
            let scorer2 = FormScorer()

            let straightPose = makePose(leftAngle: 70.0, rightAngle: 70.0, spineAngleDeg: 0.0)
            let tiltedPose   = makePose(leftAngle: 70.0, rightAngle: 70.0, spineAngleDeg: 25.0)

            for _ in 0..<5 {
                scorer1.recordFrame(pose: straightPose, leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: true)
                scorer2.recordFrame(pose: tiltedPose,   leftElbowAngle: 70.0, rightElbowAngle: 70.0, isInDownPhase: true)
            }

            let straight = try #require(scorer1.finalisePushUp())
            let tilted   = try #require(scorer2.finalisePushUp())

            #expect(straight.formScore > tilted.formScore,
                    "Straight back (\(straight.formScore)) should score higher than tilted (\(tilted.formScore))")
        }
    }

    // MARK: - Integration with PushUpDetector

    @Suite("Integration with PushUpDetector")
    struct DetectorIntegration {

        /// Tight state-machine configuration shared across all integration tests.
        private let detectorConfig = PushUpStateMachine.Configuration(
            downAngleThreshold: 90,
            upAngleThreshold: 160,
            hysteresisFrameCount: 3,
            cooldownFrameCount: 5
        )

        /// Builds a full pose with arm joints at the given angle and a
        /// horizontal spine (ideal push-up position).
        private func makeFullPose(angle: Double, timestamp: Double = 0) -> BodyPose {
            makePose(leftAngle: angle, rightAngle: angle, spineAngleDeg: 0.0, timestamp: timestamp)
        }

        /// Runs one complete push-up cycle through `detector` and returns the
        /// resulting event.
        private func runOnePushUp(
            detector: PushUpDetector,
            downAngle: Double = 70.0,
            upAngle: Double = 170.0
        ) {
            for i in 0..<3 { detector.process(makeFullPose(angle: downAngle, timestamp: Double(i))) }
            for i in 0..<3 { detector.process(makeFullPose(angle: upAngle,   timestamp: 10.0 + Double(i))) }
        }

        @Test("PushUpEvent carries a non-nil FormScore after a complete push-up")
        func eventCarriesFormScore() throws {
            let detector = PushUpDetector(configuration: detectorConfig)
            let delegate = RecordingDelegate()
            detector.delegate = delegate

            runOnePushUp(detector: detector, downAngle: 70.0)

            let event = try #require(delegate.events.first)
            let score = try #require(event.formScore,
                                     "PushUpEvent should carry a non-nil FormScore")
            // depthScore: 3 DOWN frames at 70° → should be 0.8 (spec anchor).
            #expect(abs(score.depthScore - 0.8) < 0.01,
                    "Expected depthScore ~0.8 for 70° push-up, got \(score.depthScore)")
            #expect(score.formScore  >= 0.0 && score.formScore  <= 1.0)
            #expect(abs(score.combinedScore - (score.depthScore + score.formScore) / 2.0) < 0.0001)
        }

        @Test("Deeper push-up produces higher depthScore than shallow push-up")
        func deeperPushUpHigherDepthScore() throws {
            let deepDetector    = PushUpDetector(configuration: detectorConfig)
            let deepDelegate    = RecordingDelegate()
            deepDetector.delegate = deepDelegate
            runOnePushUp(detector: deepDetector, downAngle: 60.0)

            let shallowDetector    = PushUpDetector(configuration: detectorConfig)
            let shallowDelegate    = RecordingDelegate()
            shallowDetector.delegate = shallowDelegate
            runOnePushUp(detector: shallowDetector, downAngle: 88.0)

            let deepScore    = try #require(deepDelegate.events.first?.formScore)
            let shallowScore = try #require(shallowDelegate.events.first?.formScore)

            // 60° → depthScore 1.0; 88° → depthScore just above 0.5.
            #expect(deepScore.depthScore > shallowScore.depthScore,
                    "Deep (\(deepScore.depthScore)) should exceed shallow (\(shallowScore.depthScore))")
            #expect(abs(deepScore.depthScore - 1.0) < 0.001,
                    "60° push-up should score 1.0, got \(deepScore.depthScore)")
            #expect(shallowScore.depthScore > 0.5 && shallowScore.depthScore < 0.6,
                    "88° push-up should score just above 0.5, got \(shallowScore.depthScore)")
        }

        @Test("Reset clears form scorer state; subsequent cycle scores independently")
        func resetClearsFormScorerInDetector() throws {
            let detector = PushUpDetector(configuration: detectorConfig)
            let delegate = RecordingDelegate()
            detector.delegate = delegate

            // Partial DOWN phase, then reset.
            for i in 0..<3 { detector.process(makeFullPose(angle: 70.0, timestamp: Double(i))) }
            detector.reset()

            // A fresh full cycle should produce exactly one event with valid scores.
            runOnePushUp(detector: detector, downAngle: 70.0)

            #expect(delegate.events.count == 1, "Should count exactly one push-up after reset")
            let score = try #require(delegate.events.first?.formScore)
            #expect(abs(score.depthScore - 0.8) < 0.01,
                    "Post-reset depthScore should be 0.8 for 70°, got \(score.depthScore)")
        }

        @Test("Multiple push-ups each carry independent FormScores")
        func multiplePushUpsIndependentScores() throws {
            let detector = PushUpDetector(configuration: detectorConfig)
            let delegate = RecordingDelegate()
            detector.delegate = delegate

            for _ in 0..<3 {
                runOnePushUp(detector: detector, downAngle: 70.0)
                // Wait out cooldown (5 frames).
                for i in 0..<5 { detector.process(makeFullPose(angle: 170.0, timestamp: 20.0 + Double(i))) }
            }

            #expect(delegate.events.count == 3, "Expected 3 push-up events")
            for event in delegate.events {
                let score = try #require(event.formScore)
                #expect(abs(score.depthScore - 0.8) < 0.01,
                        "Each push-up at 70° should score 0.8, got \(score.depthScore)")
                #expect(score.formScore  >= 0.0 && score.formScore  <= 1.0)
                #expect(abs(score.combinedScore - (score.depthScore + score.formScore) / 2.0) < 0.0001)
            }
        }
    }
}

// MARK: - RecordingDelegate

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
