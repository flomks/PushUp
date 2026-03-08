import Foundation
import UIKit

// MARK: - DevicePerformanceTier

/// Classifies the device into a performance tier that determines the pose
/// detection frame rate budget.
///
/// Tiers are based on the Apple Silicon generation:
/// - **high**: A14 Bionic and newer (iPhone 12+). Targets 30 FPS.
/// - **medium**: A13 Bionic (iPhone 11, SE 2nd gen). Targets ~15 FPS via
///   every-other-frame skipping.
/// - **low**: A12 Bionic and older (iPhone XS/XR, SE 1st gen). Targets
///   ~10 FPS via every-third-frame processing.
enum DevicePerformanceTier: Equatable, Sendable {

    /// A14 Bionic (iPhone 12) and newer. Full 30 FPS pose detection.
    case high

    /// A13 Bionic (iPhone 11, SE 2nd gen). Process every 2nd frame (~15 FPS
    /// pose detection at 30 FPS camera).
    case medium

    /// A12 Bionic and older. Process every 3rd frame (~10 FPS pose detection
    /// at 30 FPS camera).
    case low

    // MARK: - Frame Skip Interval

    /// Number of camera frames between pose detection runs.
    ///
    /// - `high`: 1 (every frame)
    /// - `medium`: 2 (every other frame)
    /// - `low`: 3 (every third frame)
    var frameSkipInterval: Int {
        switch self {
        case .high:   return 1
        case .medium: return 2
        case .low:    return 3
        }
    }

    /// Target pose detection rate in frames per second (approximate).
    var targetPoseDetectionFPS: Int {
        switch self {
        case .high:   return 30
        case .medium: return 15
        case .low:    return 10
        }
    }
}

// MARK: - PerformanceMonitor

/// Monitors runtime performance and adapts the pose detection frequency to
/// maintain smooth operation across device generations.
///
/// **Responsibilities**
/// - Detects the device performance tier at startup using the machine
///   identifier (e.g. `iPhone13,2` for iPhone 12).
/// - Implements frame-skip logic: `shouldProcessFrame()` returns `true` only
///   on frames that should be sent to Vision, based on the device tier and
///   any dynamic throttling.
/// - Measures actual pose detection FPS using a sliding window of timestamps.
/// - Dynamically increases the frame-skip interval when the measured FPS
///   drops significantly below the target (thermal throttling, heavy load).
/// - Publishes `currentFPS`, `isPaused`, and `tier` as `@Published`
///   properties for SwiftUI consumption.
/// - Handles app-backgrounding: pauses frame processing when the app enters
///   the background and resumes when it returns to the foreground.
///
/// **Threading model**
/// - `shouldProcessFrame()` is called from the video output queue.
/// - All `@Published` properties are updated on the **main queue**.
/// - Internal counters are protected by `NSLock` for safe cross-queue access.
///
/// **Usage**
/// ```swift
/// let monitor = PerformanceMonitor()
///
/// // Inside CameraManagerDelegate / VisionPoseDetector:
/// func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
///     guard monitor.shouldProcessFrame() else { return }
///     poseDetector.process(sampleBuffer)
/// }
///
/// // Record each completed pose detection for FPS measurement:
/// monitor.recordPoseDetectionCompleted()
/// ```
@MainActor
final class PerformanceMonitor: ObservableObject {

    // MARK: - Published State

    /// The detected device performance tier. Set once at initialisation.
    @Published private(set) var tier: DevicePerformanceTier

    /// The measured pose detection rate over the last measurement window.
    /// Updated approximately once per second on the main queue.
    @Published private(set) var currentFPS: Double = 0

    /// `true` when the monitor has paused frame processing because the app
    /// is in the background.
    @Published private(set) var isPaused: Bool = false

    // MARK: - Immutable Tier Copy (safe for nonisolated access)

    /// Immutable copy of the detected tier, safe to read from any queue
    /// without crossing the `@MainActor` isolation boundary.
    /// Set once in `init` and never mutated. The `@Published tier` property
    /// mirrors this value but is only safe to read on the main actor.
    private let _detectedTier: DevicePerformanceTier

    /// Immutable copy of the tier's frame skip interval, safe to read from
    /// any queue without crossing the `@MainActor` isolation boundary.
    /// Set once in `init` and never mutated.
    private let _tierFrameSkipInterval: Int

    /// Immutable copy of the tier's target FPS, safe to read from any queue.
    private let _tierTargetFPS: Double

    // MARK: - Configuration

    /// Tunable parameters for the performance monitor.
    struct Configuration: Sendable {

        /// Size of the sliding window (number of timestamps) used to compute
        /// the rolling FPS average.
        ///
        /// Default: 30 (approximately 1 second of pose detections at 30 FPS).
        let fpsMeasurementWindowSize: Int

        /// If the measured FPS falls below `targetFPS * dynamicThrottleRatio`,
        /// the frame-skip interval is increased by 1 to reduce CPU load.
        ///
        /// Default: 0.7 (throttle when FPS drops below 70% of target).
        let dynamicThrottleRatio: Double

        /// If the measured FPS recovers above `targetFPS * dynamicRecoveryRatio`,
        /// the frame-skip interval is decreased by 1 (down to the tier minimum).
        ///
        /// Default: 0.9 (recover when FPS is above 90% of target).
        let dynamicRecoveryRatio: Double

        /// Maximum additional frames to skip beyond the tier's base interval.
        /// Prevents the detector from becoming completely unresponsive under load.
        ///
        /// Default: 2 (so a `low` tier device can skip up to 5 frames).
        let maxAdditionalSkipFrames: Int

        init(
            fpsMeasurementWindowSize: Int = 30,
            dynamicThrottleRatio: Double = 0.7,
            dynamicRecoveryRatio: Double = 0.9,
            maxAdditionalSkipFrames: Int = 2
        ) {
            precondition(fpsMeasurementWindowSize >= 5,
                         "fpsMeasurementWindowSize must be >= 5")
            precondition(dynamicThrottleRatio > 0 && dynamicThrottleRatio < 1,
                         "dynamicThrottleRatio must be in (0, 1)")
            precondition(dynamicRecoveryRatio > dynamicThrottleRatio && dynamicRecoveryRatio <= 1,
                         "dynamicRecoveryRatio must be > dynamicThrottleRatio and <= 1")
            precondition(maxAdditionalSkipFrames >= 0,
                         "maxAdditionalSkipFrames must be >= 0")
            self.fpsMeasurementWindowSize = fpsMeasurementWindowSize
            self.dynamicThrottleRatio = dynamicThrottleRatio
            self.dynamicRecoveryRatio = dynamicRecoveryRatio
            self.maxAdditionalSkipFrames = maxAdditionalSkipFrames
        }

        static let `default` = Configuration()
    }

    // MARK: - Private State (protected by stateLock)

    private let stateLock = NSLock()
    private let configuration: Configuration

    /// Monotonically increasing counter of camera frames received.
    /// Incremented on every `shouldProcessFrame()` call.
    private var _frameCounter: UInt64 = 0

    /// The effective frame-skip interval, which may be larger than
    /// `tier.frameSkipInterval` when dynamic throttling is active.
    private var _effectiveSkipInterval: Int

    /// Additional frames being skipped due to dynamic throttling.
    private var _additionalSkipFrames: Int = 0

    /// Circular buffer of `CACurrentMediaTime()` timestamps for completed pose
    /// detections. Used to compute the rolling FPS average.
    ///
    /// Implemented as a fixed-capacity array with a write index to avoid the
    /// O(n) cost of `Array.removeFirst()` in the hot path.
    private var _detectionTimestamps: [Double] = []
    private var _timestampWriteIndex: Int = 0
    private var _timestampCount: Int = 0

    /// Timestamp of the last FPS update published to the main queue.
    private var _lastFPSUpdateTime: Double = 0

    // MARK: - Background Observation

    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    // MARK: - Init / Deinit

    /// Creates a monitor with the given configuration.
    ///
    /// - Parameters:
    ///   - configuration: Tunable parameters. Defaults to `Configuration.default`.
    ///   - overrideTier: When non-nil, bypasses device detection and uses this
    ///     tier directly. Useful for testing.
    init(
        configuration: Configuration = .default,
        overrideTier: DevicePerformanceTier? = nil
    ) {
        self.configuration = configuration
        let detectedTier = overrideTier ?? Self.detectDeviceTier()
        self.tier = detectedTier
        self._detectedTier = detectedTier
        self._tierFrameSkipInterval = detectedTier.frameSkipInterval
        self._tierTargetFPS = Double(detectedTier.targetPoseDetectionFPS)
        self._effectiveSkipInterval = detectedTier.frameSkipInterval
        subscribeToAppLifecycle()
    }

    deinit {
        if let token = backgroundObserver { NotificationCenter.default.removeObserver(token) }
        if let token = foregroundObserver { NotificationCenter.default.removeObserver(token) }
    }

    // MARK: - Public API

    /// Returns `true` when the current frame should be sent to Vision for pose
    /// detection.
    ///
    /// Call this from the video output queue for every incoming camera frame.
    /// When it returns `false`, skip the frame entirely to save CPU/battery.
    ///
    /// Thread-safe: protected by `stateLock`.
    nonisolated func shouldProcessFrame() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !_isPausedInternal else { return false }

        _frameCounter &+= 1
        return _frameCounter % UInt64(_effectiveSkipInterval) == 0
    }

    /// Records that a pose detection run has completed.
    ///
    /// Call this immediately after `VisionPoseDetector.process(_:)` returns.
    /// Used to compute the rolling FPS average and drive dynamic throttling.
    ///
    /// Thread-safe: protected by `stateLock`.
    nonisolated func recordPoseDetectionCompleted() {
        let now = CACurrentMediaTime()

        stateLock.lock()
        // Maintain a circular buffer of timestamps.
        appendTimestamp(now)

        // Compute FPS from the window.
        let fps = computeFPSFromRingBuffer()
        let targetFPS = _tierTargetFPS
        let shouldUpdateUI = now - _lastFPSUpdateTime >= 1.0
        if shouldUpdateUI { _lastFPSUpdateTime = now }

        // Dynamic throttling: increase skip interval when FPS is too low.
        if fps > 0 && fps < targetFPS * configuration.dynamicThrottleRatio {
            if _additionalSkipFrames < configuration.maxAdditionalSkipFrames {
                _additionalSkipFrames += 1
                _effectiveSkipInterval = _tierFrameSkipInterval + _additionalSkipFrames
            }
        } else if fps >= targetFPS * configuration.dynamicRecoveryRatio {
            if _additionalSkipFrames > 0 {
                _additionalSkipFrames -= 1
                _effectiveSkipInterval = _tierFrameSkipInterval + _additionalSkipFrames
            }
        }

        let capturedFPS = fps
        stateLock.unlock()

        if shouldUpdateUI {
            DispatchQueue.main.async { [weak self] in
                self?.currentFPS = capturedFPS
            }
        }
    }

    /// Resets all counters. Call when starting a new workout session.
    nonisolated func reset() {
        stateLock.lock()
        _frameCounter = 0
        _additionalSkipFrames = 0
        _effectiveSkipInterval = _tierFrameSkipInterval
        _detectionTimestamps.removeAll(keepingCapacity: true)
        _timestampWriteIndex = 0
        _timestampCount = 0
        _lastFPSUpdateTime = 0
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.currentFPS = 0
        }
    }

    // MARK: - Private: Background Handling

    /// Internal backing for `isPaused`, readable from any queue under `stateLock`.
    private var _isPausedInternal: Bool = false

    private func subscribeToAppLifecycle() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppDidEnterBackground()
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppWillEnterForeground()
        }
    }

    private func handleAppDidEnterBackground() {
        stateLock.lock()
        _isPausedInternal = true
        stateLock.unlock()
        isPaused = true
        #if DEBUG
        print("[PerformanceMonitor] App entered background – pose detection paused")
        #endif
    }

    private func handleAppWillEnterForeground() {
        stateLock.lock()
        _isPausedInternal = false
        // Reset frame counter so the first foreground frame is processed
        // immediately rather than waiting for the skip interval to align.
        _frameCounter = 0
        stateLock.unlock()
        isPaused = false
        #if DEBUG
        print("[PerformanceMonitor] App entered foreground – pose detection resumed")
        #endif
    }

    // MARK: - Private: Ring Buffer Helpers

    /// Appends a timestamp to the circular buffer. O(1) amortised.
    /// Must be called while holding `stateLock`.
    private func appendTimestamp(_ value: Double) {
        let capacity = configuration.fpsMeasurementWindowSize
        if _detectionTimestamps.count < capacity {
            _detectionTimestamps.append(value)
        } else {
            _detectionTimestamps[_timestampWriteIndex] = value
        }
        _timestampWriteIndex = (_timestampWriteIndex + 1) % capacity
        _timestampCount = min(_timestampCount + 1, capacity)
    }

    // MARK: - Private: FPS Computation

    /// Computes the rolling FPS from the circular buffer of timestamps.
    /// Must be called while holding `stateLock`.
    ///
    /// Returns 0 when fewer than 2 timestamps are available.
    private func computeFPSFromRingBuffer() -> Double {
        guard _timestampCount >= 2 else { return 0 }
        // Find the oldest and newest timestamps in the ring buffer.
        let capacity = _detectionTimestamps.count
        let oldestIndex = (_timestampWriteIndex + capacity - _timestampCount) % capacity
        let newestIndex = (_timestampWriteIndex + capacity - 1) % capacity
        let oldest = _detectionTimestamps[oldestIndex]
        let newest = _detectionTimestamps[newestIndex]
        let elapsed = newest - oldest
        guard elapsed > 0 else { return 0 }
        return Double(_timestampCount - 1) / elapsed
    }

    // MARK: - Private: Device Tier Detection

    /// Detects the device performance tier from the machine identifier.
    ///
    /// Uses `sysctlbyname("hw.machine")` to read the raw model string
    /// (e.g. `iPhone13,2` for iPhone 12). The chip generation is inferred
    /// from the model number:
    ///
    /// | Model prefix | Chip    | Tier   |
    /// |--------------|---------|--------|
    /// | iPhone13+    | A14+    | high   |
    /// | iPhone12     | A13     | medium |
    /// | iPhone11     | A12     | low    |
    /// | iPhone10     | A11     | low    |
    /// | older        | A10-    | low    |
    ///
    /// Falls back to `.medium` when the identifier cannot be read.
    static func detectDeviceTier() -> DevicePerformanceTier {
        #if targetEnvironment(simulator)
        // Simulators run on Mac hardware; always use the highest tier.
        return .high
        #else
        let identifier = machineIdentifier()
        return tier(for: identifier)
        #endif
    }

    /// Returns the raw machine identifier string from `sysctlbyname`.
    static func machineIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    /// Maps a machine identifier string to a `DevicePerformanceTier`.
    ///
    /// Exposed as a `static` pure function for unit testing.
    static func tier(for identifier: String) -> DevicePerformanceTier {
        // iPhone model numbers: iPhone{major},{minor}
        // A14 Bionic: iPhone 12 series = iPhone13,x
        // A15 Bionic: iPhone 13 series = iPhone14,x
        // A16 Bionic: iPhone 14 Pro series = iPhone15,x
        // A17 Pro: iPhone 15 Pro series = iPhone16,x
        // A18: iPhone 16 series = iPhone17,x
        //
        // A13 Bionic: iPhone 11 series = iPhone12,x; SE 2nd gen = iPhone12,8
        // A12 Bionic: iPhone XS/XR = iPhone11,x; SE 3rd gen uses A15 (iPhone14,6)
        // A11 Bionic: iPhone X/8 = iPhone10,x
        // A10 Fusion: iPhone 7 = iPhone9,x

        guard identifier.hasPrefix("iPhone") else {
            // iPad or other device: default to medium.
            return .medium
        }

        // Extract the major version number after "iPhone".
        let suffix = identifier.dropFirst("iPhone".count)
        guard let commaIndex = suffix.firstIndex(of: ","),
              let major = Int(suffix[suffix.startIndex..<commaIndex])
        else {
            return .medium
        }

        switch major {
        case 13...: // iPhone 12 and newer (A14+)
            return .high
        case 12:    // iPhone 11 series and SE 2nd gen (A13)
            return .medium
        default:    // iPhone XS/XR and older (A12 and below)
            return .low
        }
    }
}

// MARK: - PerformanceMonitor + Diagnostics

extension PerformanceMonitor {

    /// A snapshot of the monitor's internal state for diagnostics and debug UI.
    struct Diagnostics: Sendable {
        let tier: DevicePerformanceTier
        let effectiveSkipInterval: Int
        let additionalSkipFrames: Int
        let measuredFPS: Double
        let isPaused: Bool
    }

    /// Returns a snapshot of the current internal state.
    ///
    /// Thread-safe: protected by `stateLock`.
    nonisolated func diagnostics() -> Diagnostics {
        stateLock.lock()
        defer { stateLock.unlock() }
        return Diagnostics(
            tier: _detectedTier,
            effectiveSkipInterval: _effectiveSkipInterval,
            additionalSkipFrames: _additionalSkipFrames,
            measuredFPS: computeFPSFromRingBuffer(),
            isPaused: _isPausedInternal
        )
    }
}
