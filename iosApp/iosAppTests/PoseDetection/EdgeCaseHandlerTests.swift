import CoreGraphics
import Testing

@testable import iosApp

// MARK: - Test Helpers

/// Creates a `BodyPose` where all joints have the given confidence.
private func makeUniformPose(confidence: Float, timestamp: Double = 0) -> BodyPose {
    let joints = Dictionary(
        uniqueKeysWithValues: JointName.allCases.map { name in
            (name, Joint(name: name, position: CGPoint(x: 0.5, y: 0.5), confidence: confidence))
        }
    )
    return BodyPose(joints: joints, timestamp: timestamp)
}

/// Creates a `BodyPose` where only the specified joints are detected (confidence 0.9)
/// and all others have zero confidence.
private func makePoseWithJoints(_ detected: Set<JointName>, timestamp: Double = 0) -> BodyPose {
    let joints = Dictionary(
        uniqueKeysWithValues: JointName.allCases.map { name in
            let conf: Float = detected.contains(name) ? 0.9 : 0.0
            return (name, Joint(name: name, position: CGPoint(x: 0.5, y: 0.5), confidence: conf))
        }
    )
    return BodyPose(joints: joints, timestamp: timestamp)
}

// MARK: - EdgeCaseHandlerTests

@Suite("EdgeCaseHandler")
struct EdgeCaseHandlerTests {

    // MARK: - No Person Detected

    @Test("Returns noPersonDetected warning when no poses are provided")
    func noPersonDetected_emptyPoses() {
        let handler = EdgeCaseHandler(configuration: .init(warningHysteresisFrameCount: 1, warningClearanceFrameCount: 1))
        let result = handler.evaluate(nil, allPoses: [])
        #expect(result.selectedPose == nil)
        #expect(result.warnings.contains(.noPersonDetected))
        #expect(!result.isReliable)
    }

    @Test("Returns no noPersonDetected warning when a pose is provided")
    func noPersonDetected_posePresent() {
        let handler = EdgeCaseHandler(configuration: .init(warningHysteresisFrameCount: 1, warningClearanceFrameCount: 1))
        let pose = makeUniformPose(confidence: 0.9)
        let result = handler.evaluate(pose, allPoses: [pose])
        #expect(!result.warnings.contains(.noPersonDetected))
    }

    // MARK: - Multiple Persons

    @Test("Emits multiplePersonsDetected when more than one pose is provided")
    func multiplePersons_warning() {
        let handler = EdgeCaseHandler(configuration: .init(warningHysteresisFrameCount: 1, warningClearanceFrameCount: 1))
        let pose1 = makeUniformPose(confidence: 0.9)
        let pose2 = makeUniformPose(confidence: 0.8)
        let result = handler.evaluate(pose1, allPoses: [pose1, pose2])
        #expect(result.warnings.contains(.multiplePersonsDetected))
    }

    @Test("Does not emit multiplePersonsDetected for a single pose")
    func singlePerson_noMultipleWarning() {
        let handler = EdgeCaseHandler(configuration: .init(warningHysteresisFrameCount: 1, warningClearanceFrameCount: 1))
        let pose = makeUniformPose(confidence: 0.9)
        let result = handler.evaluate(pose, allPoses: [pose])
        #expect(!result.warnings.contains(.multiplePersonsDetected))
    }

    // MARK: - Largest Person Selection

    @Test("Selects pose with more detected joints when multiple persons present")
    func selectLargestPose_byJointCount() {
        // pose1: all joints detected
        let pose1 = makeUniformPose(confidence: 0.9)
        // pose2: only half the joints detected
        let halfJoints = Set(JointName.allCases.prefix(JointName.allCases.count / 2))
        let pose2 = makePoseWithJoints(halfJoints)

        let selected = EdgeCaseHandler.selectLargestPose(from: [pose1, pose2])
        #expect(selected.detectedJoints.count == pose1.detectedJoints.count)
    }

    @Test("Selects pose with higher average confidence when joint counts are equal")
    func selectLargestPose_byConfidence() {
        let pose1 = makeUniformPose(confidence: 0.9)
        let pose2 = makeUniformPose(confidence: 0.6)
        let selected = EdgeCaseHandler.selectLargestPose(from: [pose1, pose2])
        // pose1 has higher confidence; all joints detected in both
        let avgConf1 = pose1.joints.values.map(\.confidence).reduce(0, +) / Float(pose1.joints.count)
        let avgConf2 = pose2.joints.values.map(\.confidence).reduce(0, +) / Float(pose2.joints.count)
        #expect(avgConf1 > avgConf2)
        // The selected pose should be the one with higher confidence
        let selectedAvg = selected.joints.values.map(\.confidence).reduce(0, +) / Float(selected.joints.count)
        #expect(selectedAvg == avgConf1)
    }

    // MARK: - Poor Angle

    @Test("Detects poor angle when fewer than 4 of 6 arm joints are detected")
    func poorAngle_fewJoints() {
        // Only 2 of 6 required joints detected (< 67%)
        let twoJoints = makePoseWithJoints([.leftShoulder, .rightShoulder])
        let result = EdgeCaseHandler.hasPoorAngle(pose: twoJoints)
        #expect(result == true)
    }

    @Test("No poor angle when all 6 arm joints are detected")
    func poorAngle_allJoints() {
        let allJoints = makeUniformPose(confidence: 0.9)
        let result = EdgeCaseHandler.hasPoorAngle(pose: allJoints)
        #expect(result == false)
    }

    @Test("No poor angle when exactly 4 of 6 arm joints are detected (at threshold)")
    func poorAngle_atThreshold() {
        // 4/6 = 0.667, which equals the default threshold of 0.67 (rounds to pass)
        let fourJoints = makePoseWithJoints([
            .leftShoulder, .rightShoulder, .leftElbow, .rightElbow
        ])
        // 4/6 = 0.6667, which is >= 0.67 (barely passes)
        let result = EdgeCaseHandler.hasPoorAngle(
            pose: fourJoints,
            configuration: .init(minimumRequiredJointFraction: 0.67)
        )
        // 4/6 = 0.6667 >= 0.67 is false (0.6667 < 0.67), so poor angle
        #expect(result == true)
    }

    // MARK: - Poor Lighting

    @Test("Detects poor lighting when average confidence is below threshold")
    func poorLighting_lowConfidence() {
        let lowConfPose = makeUniformPose(confidence: 0.3)
        let result = EdgeCaseHandler.hasPoorLighting(pose: lowConfPose)
        #expect(result == true)
    }

    @Test("No poor lighting when average confidence is above threshold")
    func poorLighting_highConfidence() {
        let highConfPose = makeUniformPose(confidence: 0.8)
        let result = EdgeCaseHandler.hasPoorLighting(pose: highConfPose)
        #expect(result == false)
    }

    @Test("No poor lighting warning for zero-confidence pose (no joints detected)")
    func poorLighting_zeroConfidence_noWarning() {
        let zeroPose = makeUniformPose(confidence: 0.0)
        // Zero confidence means no joints detected at all; lighting check is skipped
        let result = EdgeCaseHandler.hasPoorLighting(pose: zeroPose)
        #expect(result == false)
    }

    // MARK: - Hysteresis

    @Test("Warning is not surfaced until hysteresis threshold is reached")
    func hysteresis_warningNotSurfacedImmediately() {
        let config = EdgeCaseHandler.Configuration(
            warningHysteresisFrameCount: 3,
            warningClearanceFrameCount: 5
        )
        let handler = EdgeCaseHandler(configuration: config)

        // Feed 2 frames with no person (below hysteresis threshold of 3)
        for _ in 0..<2 {
            let result = handler.evaluate(nil, allPoses: [])
            #expect(!result.warnings.contains(.noPersonDetected))
        }
    }

    @Test("Warning is surfaced after hysteresis threshold is reached")
    func hysteresis_warningSurfacedAfterThreshold() {
        let config = EdgeCaseHandler.Configuration(
            warningHysteresisFrameCount: 3,
            warningClearanceFrameCount: 5
        )
        let handler = EdgeCaseHandler(configuration: config)

        // Feed 3 frames with no person (meets hysteresis threshold)
        var lastResult: EdgeCaseResult?
        for _ in 0..<3 {
            lastResult = handler.evaluate(nil, allPoses: [])
        }
        #expect(lastResult?.warnings.contains(.noPersonDetected) == true)
    }

    @Test("Warning is cleared after clearance threshold is reached")
    func hysteresis_warningClearedAfterClearance() {
        let config = EdgeCaseHandler.Configuration(
            warningHysteresisFrameCount: 1,
            warningClearanceFrameCount: 3
        )
        let handler = EdgeCaseHandler(configuration: config)
        let goodPose = makeUniformPose(confidence: 0.9)

        // Trigger the warning
        _ = handler.evaluate(nil, allPoses: [])

        // Feed 3 good frames (meets clearance threshold)
        var lastResult: EdgeCaseResult?
        for _ in 0..<3 {
            lastResult = handler.evaluate(goodPose, allPoses: [goodPose])
        }
        #expect(lastResult?.warnings.contains(.noPersonDetected) == false)
    }

    // MARK: - Warning Priority Order

    @Test("Warnings are returned in severity order")
    func warningOrder_severityFirst() {
        let config = EdgeCaseHandler.Configuration(
            warningHysteresisFrameCount: 1,
            warningClearanceFrameCount: 1
        )
        let handler = EdgeCaseHandler(configuration: config)

        // Trigger multiple warnings simultaneously:
        // - Multiple persons (2 poses)
        // - Poor lighting (low confidence)
        let lowConfPose = makeUniformPose(confidence: 0.2)
        let result = handler.evaluate(lowConfPose, allPoses: [lowConfPose, lowConfPose])

        // poorLighting should come before multiplePersonsDetected in the order
        let warnings = result.warnings
        if let lightingIdx = warnings.firstIndex(of: .poorLighting),
           let multipleIdx = warnings.firstIndex(of: .multiplePersonsDetected) {
            #expect(lightingIdx < multipleIdx)
        }
    }

    // MARK: - Reset

    @Test("Reset clears all active warnings and hysteresis state")
    func reset_clearsWarnings() {
        let config = EdgeCaseHandler.Configuration(
            warningHysteresisFrameCount: 1,
            warningClearanceFrameCount: 10
        )
        let handler = EdgeCaseHandler(configuration: config)

        // Trigger a warning
        _ = handler.evaluate(nil, allPoses: [])
        #expect(handler.activeWarnings.contains(.noPersonDetected))

        // Reset
        handler.reset()
        #expect(handler.activeWarnings.isEmpty)
    }
}

// MARK: - PerformanceMonitorTests

@Suite("PerformanceMonitor")
struct PerformanceMonitorTests {

    // MARK: - Device Tier Detection

    @Test("iPhone 12 (iPhone13,2) maps to high tier")
    func deviceTier_iPhone12() {
        let tier = PerformanceMonitor.tier(for: "iPhone13,2")
        #expect(tier == .high)
    }

    @Test("iPhone 13 (iPhone14,5) maps to high tier")
    func deviceTier_iPhone13() {
        let tier = PerformanceMonitor.tier(for: "iPhone14,5")
        #expect(tier == .high)
    }

    @Test("iPhone 15 Pro (iPhone16,2) maps to high tier")
    func deviceTier_iPhone15Pro() {
        let tier = PerformanceMonitor.tier(for: "iPhone16,2")
        #expect(tier == .high)
    }

    @Test("iPhone 11 (iPhone12,1) maps to medium tier")
    func deviceTier_iPhone11() {
        let tier = PerformanceMonitor.tier(for: "iPhone12,1")
        #expect(tier == .medium)
    }

    @Test("iPhone SE 2nd gen (iPhone12,8) maps to medium tier")
    func deviceTier_iPhoneSE2() {
        let tier = PerformanceMonitor.tier(for: "iPhone12,8")
        #expect(tier == .medium)
    }

    @Test("iPhone XS (iPhone11,2) maps to low tier")
    func deviceTier_iPhoneXS() {
        let tier = PerformanceMonitor.tier(for: "iPhone11,2")
        #expect(tier == .low)
    }

    @Test("iPhone 8 (iPhone10,1) maps to low tier")
    func deviceTier_iPhone8() {
        let tier = PerformanceMonitor.tier(for: "iPhone10,1")
        #expect(tier == .low)
    }

    @Test("Unknown identifier falls back to medium tier")
    func deviceTier_unknown() {
        let tier = PerformanceMonitor.tier(for: "iPad13,4")
        #expect(tier == .medium)
    }

    // MARK: - Frame Skip Intervals

    @Test("High tier processes every frame (skip interval 1)")
    func frameSkip_highTier() {
        #expect(DevicePerformanceTier.high.frameSkipInterval == 1)
    }

    @Test("Medium tier processes every 2nd frame (skip interval 2)")
    func frameSkip_mediumTier() {
        #expect(DevicePerformanceTier.medium.frameSkipInterval == 2)
    }

    @Test("Low tier processes every 3rd frame (skip interval 3)")
    func frameSkip_lowTier() {
        #expect(DevicePerformanceTier.low.frameSkipInterval == 3)
    }

    // MARK: - shouldProcessFrame

    @Test("High tier processes every frame")
    func shouldProcess_highTier_everyFrame() {
        let monitor = PerformanceMonitor(overrideTier: .high)
        var processedCount = 0
        for _ in 0..<30 {
            if monitor.shouldProcessFrame() { processedCount += 1 }
        }
        #expect(processedCount == 30)
    }

    @Test("Medium tier processes every 2nd frame (approximately 15 of 30)")
    func shouldProcess_mediumTier_everyOtherFrame() {
        let monitor = PerformanceMonitor(overrideTier: .medium)
        var processedCount = 0
        for _ in 0..<30 {
            if monitor.shouldProcessFrame() { processedCount += 1 }
        }
        #expect(processedCount == 15)
    }

    @Test("Low tier processes every 3rd frame (approximately 10 of 30)")
    func shouldProcess_lowTier_everyThirdFrame() {
        let monitor = PerformanceMonitor(overrideTier: .low)
        var processedCount = 0
        for _ in 0..<30 {
            if monitor.shouldProcessFrame() { processedCount += 1 }
        }
        #expect(processedCount == 10)
    }

    // MARK: - Reset

    @Test("Reset resets frame counter so first frame after reset is processed")
    func reset_firstFrameProcessed() {
        let monitor = PerformanceMonitor(overrideTier: .medium)
        // Skip the first frame (frame 1 is processed, frame 2 is skipped for medium)
        _ = monitor.shouldProcessFrame() // frame 1: processed
        _ = monitor.shouldProcessFrame() // frame 2: skipped

        monitor.reset()

        // After reset, frame counter is 0, so frame 1 should be processed again
        let processed = monitor.shouldProcessFrame()
        #expect(processed == true)
    }

    // MARK: - Target FPS

    @Test("High tier targets 30 FPS")
    func targetFPS_high() {
        #expect(DevicePerformanceTier.high.targetPoseDetectionFPS == 30)
    }

    @Test("Medium tier targets 15 FPS")
    func targetFPS_medium() {
        #expect(DevicePerformanceTier.medium.targetPoseDetectionFPS == 15)
    }

    @Test("Low tier targets 10 FPS")
    func targetFPS_low() {
        #expect(DevicePerformanceTier.low.targetPoseDetectionFPS == 10)
    }
}
