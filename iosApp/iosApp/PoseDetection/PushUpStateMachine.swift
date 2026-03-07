// MARK: - PushUpPhase

/// The discrete phases of a push-up cycle tracked by `PushUpStateMachine`.
///
/// The valid progression is:
/// ```
/// IDLE -> DOWN -> COOLDOWN -> IDLE
/// ```
/// A push-up is counted at the moment the machine transitions from DOWN to
/// COOLDOWN (i.e. when the UP angle threshold is held for the required number
/// of consecutive frames). A partial cycle (DOWN without a subsequent UP) does
/// **not** count.
enum PushUpPhase: Equatable, Sendable {

    /// No push-up in progress. The person is either standing, resting, or the
    /// elbow angle is above the DOWN threshold.
    case idle

    /// The person has lowered into the bottom of the push-up.
    /// Entered when the elbow angle drops below `Configuration.downAngleThreshold`
    /// for at least `Configuration.hysteresisFrameCount` consecutive frames.
    case down

    /// A cooldown period immediately after a push-up is counted.
    /// Prevents double-counting when the angle briefly dips back below the
    /// UP threshold before the person fully resets.
    case cooldown
}

// MARK: - PushUpStateMachine.Configuration

extension PushUpStateMachine {

    /// Tunable parameters for the state machine.
    ///
    /// All thresholds are in **degrees**. All frame counts assume the detector
    /// runs at approximately 30 FPS; adjust `hysteresisFrameCount` and
    /// `cooldownFrameCount` proportionally for other frame rates.
    struct Configuration: Sendable {

        // MARK: Angle thresholds

        /// Elbow angle (degrees) below which the DOWN phase is entered.
        /// Default: 90°. A fully bent elbow at the bottom of a push-up is
        /// typically 60–80°; 90° gives a comfortable margin.
        let downAngleThreshold: Double

        /// Elbow angle (degrees) above which the push-up is counted (UP phase).
        /// Default: 160°. A fully extended elbow is ~170–180°; 160° avoids
        /// requiring perfect lockout.
        let upAngleThreshold: Double

        // MARK: Hysteresis

        /// Number of consecutive frames that must show the new angle condition
        /// before a state transition is accepted.
        ///
        /// Higher values reduce noise-induced false transitions at the cost of
        /// slightly delayed counting. At 30 FPS, 3 frames ≈ 100 ms.
        /// Must be >= 1.
        let hysteresisFrameCount: Int

        // MARK: Cooldown

        /// Number of frames to remain in `.cooldown` after a push-up is counted.
        ///
        /// At 30 FPS, 15 frames ≈ 500 ms. This prevents a single push-up from
        /// being counted twice if the angle briefly oscillates around the UP
        /// threshold at the top of the movement.
        /// Must be >= 1.
        let cooldownFrameCount: Int

        // MARK: Init

        /// Creates a configuration with the given parameters.
        ///
        /// - Precondition: `downAngleThreshold` < `upAngleThreshold`
        /// - Precondition: `hysteresisFrameCount` >= 1
        /// - Precondition: `cooldownFrameCount` >= 1
        init(
            downAngleThreshold: Double = 90.0,
            upAngleThreshold: Double = 160.0,
            hysteresisFrameCount: Int = 3,
            cooldownFrameCount: Int = 15
        ) {
            precondition(
                downAngleThreshold < upAngleThreshold,
                "downAngleThreshold (\(downAngleThreshold)) must be less than upAngleThreshold (\(upAngleThreshold))"
            )
            precondition(
                hysteresisFrameCount >= 1,
                "hysteresisFrameCount must be >= 1, got \(hysteresisFrameCount)"
            )
            precondition(
                cooldownFrameCount >= 1,
                "cooldownFrameCount must be >= 1, got \(cooldownFrameCount)"
            )
            self.downAngleThreshold  = downAngleThreshold
            self.upAngleThreshold    = upAngleThreshold
            self.hysteresisFrameCount = hysteresisFrameCount
            self.cooldownFrameCount  = cooldownFrameCount
        }

        // MARK: Defaults

        /// The default configuration used when none is supplied.
        static let `default` = Configuration()
    }
}

// MARK: - PushUpStateMachine

/// A finite-state machine that recognises complete push-up cycles from a
/// stream of elbow-angle measurements.
///
/// **State diagram**
/// ```
/// IDLE     --[angle < downThreshold for N frames]--> DOWN
/// DOWN     --[angle > upThreshold   for N frames]--> COOLDOWN  (push-up counted)
/// COOLDOWN --[after M frames]                     --> IDLE
/// ```
///
/// **Hysteresis**
/// Each transition requires the triggering condition to hold for
/// `configuration.hysteresisFrameCount` consecutive frames. A single
/// out-of-range frame resets the pending-transition counter without changing
/// the current phase.
///
/// **Cooldown**
/// After a push-up is counted the machine enters `.cooldown` for
/// `configuration.cooldownFrameCount` frames before returning to `.idle`.
/// This prevents double-counting when the elbow angle briefly dips below the
/// UP threshold at the top of the movement.
///
/// **Thread safety**
/// `PushUpStateMachine` is **not** thread-safe. All calls to `update(angle:)`
/// must come from the same serial queue (typically the video output queue).
final class PushUpStateMachine {

    // MARK: - Public State

    /// The current phase of the push-up cycle.
    private(set) var phase: PushUpPhase = .idle

    /// Total number of complete push-ups counted since the machine was created
    /// or last reset.
    private(set) var pushUpCount: Int = 0

    // MARK: - Configuration

    let configuration: Configuration

    // MARK: - Private Counters

    /// Number of consecutive frames that have satisfied the condition for the
    /// *next* state. Reset to 0 whenever the condition is not met.
    private var pendingFrameCount: Int = 0

    /// Counts down from `configuration.cooldownFrameCount` to 0 while in the
    /// `.cooldown` phase.
    private var cooldownFramesRemaining: Int = 0

    // MARK: - Init

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Feeds a new elbow-angle measurement into the state machine.
    ///
    /// - Parameter angle: The elbow angle in degrees for the current frame.
    ///   Pass `nil` when the pose is not detected or confidence is too low;
    ///   the machine will treat this as a "no-op" frame (pending counters are
    ///   not advanced, but cooldown still ticks down).
    /// - Returns: `true` if a push-up was counted on this frame, `false` otherwise.
    @discardableResult
    func update(angle: Double?) -> Bool {
        switch phase {
        case .idle:
            return handleIdle(angle: angle)
        case .down:
            return handleDown(angle: angle)
        case .cooldown:
            return handleCooldown()
        }
    }

    /// Resets the state machine to its initial state without changing the
    /// configuration. The push-up count is also reset.
    func reset() {
        phase = .idle
        pushUpCount = 0
        pendingFrameCount = 0
        cooldownFramesRemaining = 0
    }

    // MARK: - Phase Handlers

    private func handleIdle(angle: Double?) -> Bool {
        guard let angle else {
            pendingFrameCount = 0
            return false
        }

        if angle < configuration.downAngleThreshold {
            pendingFrameCount += 1
            if pendingFrameCount >= configuration.hysteresisFrameCount {
                phase = .down
                pendingFrameCount = 0
            }
        } else {
            pendingFrameCount = 0
        }
        return false
    }

    private func handleDown(angle: Double?) -> Bool {
        guard let angle else {
            // Missing pose: reset pending counter but stay in DOWN.
            pendingFrameCount = 0
            return false
        }

        if angle > configuration.upAngleThreshold {
            pendingFrameCount += 1
            if pendingFrameCount >= configuration.hysteresisFrameCount {
                // Full cycle complete: count the push-up and enter cooldown.
                pushUpCount += 1
                phase = .cooldown
                cooldownFramesRemaining = configuration.cooldownFrameCount
                pendingFrameCount = 0
                return true
            }
        } else {
            pendingFrameCount = 0
        }
        return false
    }

    private func handleCooldown() -> Bool {
        cooldownFramesRemaining -= 1
        if cooldownFramesRemaining == 0 {
            phase = .idle
        }
        return false
    }
}
