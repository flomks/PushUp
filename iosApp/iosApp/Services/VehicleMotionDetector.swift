import CoreMotion
import Foundation

/// Detects vehicle (automotive) motion during a jogging session using on-device
/// CoreMotion activity recognition — no network calls, fully offline.
///
/// `CMMotionActivityManager` fuses accelerometer, gyroscope, and barometer data with
/// on-device ML to classify motion as: stationary, walking, running, cycling, or
/// **automotive**. We use the automotive classification to suppress distance counting
/// when the runner is clearly inside a vehicle.
///
/// **Permission:** Requires `NSMotionUsageDescription` in Info.plist.
/// **Availability:** A14 Bionic and later; older devices fall back gracefully to no-op.
@MainActor
final class VehicleMotionDetector: ObservableObject {

    // MARK: - Published State

    /// True when CoreMotion confidently reports the device is in an automotive vehicle.
    /// Updated on the main queue from the CoreMotion callback.
    @Published private(set) var isInVehicle: Bool = false

    // MARK: - Private

    private let activityManager = CMMotionActivityManager()
    private var isMonitoring: Bool = false

    // MARK: - Public API

    /// Whether activity recognition is supported on this device.
    static var isAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

    /// Starts monitoring motion activity. No-op if already monitoring or unavailable.
    func startMonitoring() {
        guard Self.isAvailable, !isMonitoring else { return }
        isMonitoring = true

        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            Task { @MainActor in
                // Only flag medium/high confidence to avoid false positives.
                // Low-confidence automotive can trigger briefly on elevators/escalators.
                let inVehicle = activity.automotive && activity.confidence != .low
                if self.isInVehicle != inVehicle {
                    self.isInVehicle = inVehicle

                    #if DEBUG
                    if inVehicle {
                        print("[VehicleMotionDetector] Automotive motion detected (confidence: \(activity.confidence.rawValue))")
                    } else {
                        print("[VehicleMotionDetector] Automotive motion cleared")
                    }
                    #endif
                }
            }
        }

        #if DEBUG
        print("[VehicleMotionDetector] Started monitoring")
        #endif
    }

    /// Stops monitoring and resets state.
    func stopMonitoring() {
        guard isMonitoring else { return }
        activityManager.stopActivityUpdates()
        isMonitoring = false
        isInVehicle = false

        #if DEBUG
        print("[VehicleMotionDetector] Stopped monitoring")
        #endif
    }
}
