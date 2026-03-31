import CoreLocation
import Foundation

/// 1-D Kalman filter applied independently to latitude and longitude.
///
/// This is the standard approach for smoothing GPS traces in fitness tracking apps
/// (used conceptually by OpenTracks, GPSLogger, RunKeeper, and described extensively
/// in the GPS tracking literature). It reduces:
/// - GPS drift while stationary (prevents fake distance accumulation)
/// - Zig-zag noise when running (points "beside the road" effect)
///
/// **How it works:**
/// The filter maintains a running position estimate and a variance (uncertainty).
/// Each new GPS fix is weighted against the current estimate based on its reported
/// horizontal accuracy: accurate fixes move the estimate more, inaccurate ones less.
/// Over time (between fixes) the uncertainty grows proportionally to assumed movement speed.
///
/// **Key parameter — `processingSpeedMetersPerSecond`:**
/// This is the assumed maximum movement speed used to model how much the true position
/// could have changed between two fixes. For jogging: ~3 m/s. Higher = tracks fast
/// direction changes better but passes more noise. Lower = smoother but lags on sharp turns.
final class GPSKalmanFilter {

    // MARK: - Configuration

    /// Assumed maximum movement speed in m/s for the noise model.
    /// 3 m/s ≈ 10.8 km/h — covers brisk jogging without over-smoothing turns.
    private let processingSpeedMetersPerSecond: Double = 3.0

    /// Floor for GPS accuracy to prevent a single very-accurate fix from locking
    /// the estimate and ignoring subsequent updates. 3m is the best consumer GPS achieves.
    private let minimumAccuracyMeters: Double = 3.0

    // MARK: - State

    private var filteredLat: Double = 0
    private var filteredLng: Double = 0
    /// Kalman variance (m²). Negative = uninitialized.
    private var variance: Double = -1
    private var lastTimestamp: Date = .distantPast

    // MARK: - Public API

    var isInitialized: Bool { variance >= 0 }

    /// Feeds a new GPS fix through the filter and returns the smoothed coordinate.
    ///
    /// - Parameters:
    ///   - coordinate: Raw GPS coordinate from CoreLocation.
    ///   - accuracy: Horizontal accuracy in metres (`CLLocation.horizontalAccuracy`).
    ///   - timestamp: Fix timestamp.
    /// - Returns: Kalman-smoothed coordinate.
    func filter(coordinate: CLLocationCoordinate2D, accuracy: Double, timestamp: Date) -> CLLocationCoordinate2D {
        let clampedAccuracy = max(accuracy, minimumAccuracyMeters)

        guard isInitialized else {
            // First fix: initialise the estimate from the raw measurement.
            filteredLat = coordinate.latitude
            filteredLng = coordinate.longitude
            variance = clampedAccuracy * clampedAccuracy
            lastTimestamp = timestamp
            return coordinate
        }

        let dt = max(0, timestamp.timeIntervalSince(lastTimestamp))
        lastTimestamp = timestamp

        // --- Predict step ---
        // Uncertainty grows over time assuming movement at processingSpeedMetersPerSecond.
        if dt > 0 {
            let processNoise = processingSpeedMetersPerSecond * processingSpeedMetersPerSecond * dt
            variance += processNoise
        }

        // --- Update step ---
        let measurementVariance = clampedAccuracy * clampedAccuracy
        // Kalman gain: how much to trust the new measurement vs. our prediction.
        let kalmanGain = variance / (variance + measurementVariance)

        filteredLat += kalmanGain * (coordinate.latitude  - filteredLat)
        filteredLng += kalmanGain * (coordinate.longitude - filteredLng)
        variance     = (1.0 - kalmanGain) * variance

        return CLLocationCoordinate2D(latitude: filteredLat, longitude: filteredLng)
    }

    /// Resets the filter state (call when starting a new tracking session).
    func reset() {
        variance = -1
        lastTimestamp = .distantPast
    }
}
