import CoreGraphics

// MARK: - PushUpVariant

/// The type of push-up being performed, classified by relative body position.
enum PushUpVariant: String, Sendable {
    /// Not yet determined or person is not in push-up position.
    case unknown  = "?"
    /// Standard push-up: hands and feet at roughly the same height.
    case normal   = "Normal"
    /// Decline push-up: feet elevated above hands (harder).
    case decline  = "Decline"
    /// Incline push-up: hands elevated above feet (easier).
    case incline  = "Incline"
}

// MARK: - PositionState

/// The current body position classification for a single frame.
struct PositionState: Sendable {
    /// Whether the person's body is roughly horizontal (push-up position).
    var isHorizontal: Bool = false
    /// The detected push-up variant (only meaningful when `isHorizontal`).
    var variant: PushUpVariant = .unknown
}

// MARK: - PositionClassifier

/// Classifies whether the person is in a horizontal push-up position and
/// which variant (Normal / Decline / Incline) they are performing.
///
/// **Horizontal detection** uses normalised Vision Y-coordinates (0 = bottom,
/// 1 = top in Vision space). When shoulder-Y and hip-Y are close together,
/// the person is lying roughly horizontal.
///
/// **Variant detection** compares the vertical positions of shoulders vs
/// ankles. For Incline, both wrists must be higher than both shoulders AND
/// higher than ankles (prevents false positives from camera perspective).
///
/// All transitions are hysteresised to prevent flickering.
///
/// **Thread safety**: Not thread-safe. Call from the video output queue only.
final class PositionClassifier {

    // MARK: - Configuration

    struct Configuration: Sendable {
        /// Max |shoulder_y - hip_y| in normalised coords for horizontal detection.
        let horizontalYDiff: CGFloat
        /// Frames the horizontal condition must hold before confirming.
        let horizontalConfirmFrames: Int
        /// Min vertical difference (normalised) between shoulder and ankle
        /// for variant classification.
        let variantThreshold: CGFloat
        /// Frames a variant must be stable before switching.
        let variantConfirmFrames: Int

        static let `default` = Configuration(
            horizontalYDiff: 0.15,
            horizontalConfirmFrames: 10,
            variantThreshold: 0.06,
            variantConfirmFrames: 20
        )
    }

    // MARK: - State

    private(set) var state = PositionState()

    private let config: Configuration
    private var horizCounter: Int = 0
    private var variantCounters: [PushUpVariant: Int] = [:]

    // MARK: - Init

    init(configuration: Configuration = .default) {
        self.config = configuration
    }

    // MARK: - Public API

    /// Updates the classifier with the current frame's pose.
    ///
    /// - Parameter pose: The body pose for this frame, or `nil` when no person
    ///   is detected. Uses normalised Vision coordinates (origin bottom-left).
    /// - Returns: The updated `PositionState`.
    @discardableResult
    func update(pose: BodyPose?) -> PositionState {
        guard let pose else {
            decay()
            return state
        }

        // ── Horizontal detection ─────────────────────────────────────────
        let shoulderY = midY(pose.leftShoulder, pose.rightShoulder)
        let hipY      = midY(pose.leftHip,      pose.rightHip)

        let isHorizNow: Bool
        if let sy = shoulderY, let hy = hipY {
            isHorizNow = abs(sy - hy) < config.horizontalYDiff
        } else {
            isHorizNow = false
        }

        if isHorizNow {
            horizCounter = min(horizCounter + 1, config.horizontalConfirmFrames)
        } else {
            horizCounter = max(horizCounter - 1, 0)
        }
        state.isHorizontal = horizCounter >= config.horizontalConfirmFrames

        // ── Variant detection (only when horizontal) ─────────────────────
        guard state.isHorizontal else {
            variantCounters.removeAll()
            state.variant = .unknown
            return state
        }

        let ankleY = midY(pose.leftAnkle, pose.rightAnkle)

        guard let sy = shoulderY, let ay = ankleY else {
            state.variant = .normal
            return state
        }

        // In Vision coordinates: Y increases upward.
        // shoulder_y > ankle_y means shoulders are higher than ankles.
        //
        // For Incline: both wrists must be higher than shoulders AND ankles.
        let lwY = pose.leftWrist?.isDetected == true ? pose.leftWrist?.position.y : nil
        let rwY = pose.rightWrist?.isDetected == true ? pose.rightWrist?.position.y : nil

        let rawVariant: PushUpVariant

        // Check Incline first: both wrists higher than shoulders and ankles
        if let lw = lwY, let rw = rwY {
            let lwAboveShoulder = (lw - sy) > config.variantThreshold
            let rwAboveShoulder = (rw - sy) > config.variantThreshold
            let lwAboveAnkle    = (lw - ay) > config.variantThreshold
            let rwAboveAnkle    = (rw - ay) > config.variantThreshold
            if lwAboveShoulder && rwAboveShoulder && lwAboveAnkle && rwAboveAnkle {
                rawVariant = .incline
            } else if (ay - sy) > config.variantThreshold {
                // Ankles higher than shoulders in Vision coords = feet elevated = Decline
                rawVariant = .decline
            } else {
                rawVariant = .normal
            }
        } else if (ay - sy) > config.variantThreshold {
            rawVariant = .decline
        } else {
            rawVariant = .normal
        }

        // Hysteresis
        for v in [PushUpVariant.normal, .decline, .incline] {
            if v == rawVariant {
                variantCounters[v] = min(
                    (variantCounters[v] ?? 0) + 1,
                    config.variantConfirmFrames
                )
            } else {
                variantCounters[v] = max((variantCounters[v] ?? 0) - 1, 0)
            }
        }

        // Winner: highest counter that reached the confirmation threshold
        var bestVariant = PushUpVariant.normal
        var bestCount = 0
        for (v, c) in variantCounters where c >= config.variantConfirmFrames && c > bestCount {
            bestVariant = v
            bestCount = c
        }
        state.variant = bestVariant

        return state
    }

    /// Resets all state. Call when starting a new workout session.
    func reset() {
        state = PositionState()
        horizCounter = 0
        variantCounters.removeAll()
    }

    // MARK: - Private

    private func decay() {
        horizCounter = max(horizCounter - 1, 0)
        if horizCounter == 0 {
            state.isHorizontal = false
            state.variant = .unknown
        }
    }

    /// Returns the average Y of two joints (using whichever is detected),
    /// or `nil` if neither is detected.
    private func midY(_ a: Joint?, _ b: Joint?) -> CGFloat? {
        let da = a?.isDetected == true ? a : nil
        let db = b?.isDetected == true ? b : nil
        switch (da, db) {
        case let (a?, b?): return (a.position.y + b.position.y) / 2
        case let (a?, nil): return a.position.y
        case let (nil, b?): return b.position.y
        case (nil, nil):    return nil
        }
    }
}
