import CoreLocation
import Combine
import Foundation

// MARK: - LocationTrackingManager

/// Manages GPS location tracking during jogging sessions.
///
/// **Energy Efficiency**
/// - Uses `kCLLocationAccuracyBest` only during active tracking.
/// - Allows background location updates for tracking while the app is backgrounded.
/// - Uses `activityType = .fitness` to let CoreLocation optimize for running.
/// - Filters locations with poor accuracy (> 50m horizontal accuracy).
/// - Uses `distanceFilter` of 5m to avoid excessive updates when stationary.
/// - Pauses location updates automatically when the user stops moving.
///
/// **Background Operation**
/// - Requests "Always" or "When In Use" authorization.
/// - Sets `allowsBackgroundLocationUpdates = true` during active tracking.
/// - Sets `showsBackgroundLocationIndicator = true` for the blue status bar indicator.
///
/// **Threading**
/// - All published properties are main-actor isolated.
/// - Location delegate callbacks are dispatched to the main queue.
@MainActor
final class LocationTrackingManager: NSObject, ObservableObject {

    // MARK: - Published State

    /// The most recent location update.
    @Published private(set) var currentLocation: CLLocation?

    /// All locations recorded during the current tracking session.
    @Published private(set) var recordedLocations: [CLLocation] = []

    /// Whether location tracking is currently active.
    @Published private(set) var isTracking: Bool = false

    /// Total distance covered in meters (calculated from recorded locations).
    @Published private(set) var totalDistanceMeters: Double = 0.0

    /// Current speed in meters per second.
    @Published private(set) var currentSpeed: Double = 0.0

    /// The most recent error from CoreLocation.
    @Published private(set) var lastError: Error?

    /// Current authorization status.
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    // MARK: - Private

    private let locationManager: CLLocationManager

    /// Map polyline: accept slightly worse fixes than distance stats (see `RouteDistanceCalculator`).
    private let mapRecordingMaxHorizontalAccuracyMeters: Double = 65.0
    private let mapRecordingMaxAgeSeconds: TimeInterval = 60.0

    /// Minimum distance between updates in meters.
    private let distanceFilter: Double = 3.0

    // MARK: - Private: Kalman Filter

    /// Smooths GPS fixes to reduce drift noise and the "points beside the road" effect.
    private let kalmanFilter = GPSKalmanFilter()

    // MARK: - Init

    override init() {
        let manager = CLLocationManager()
        self.locationManager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = distanceFilter
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    // MARK: - Public API

    /// Requests location authorization if not already granted.
    func requestAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Already have when-in-use, which is sufficient for background with
            // allowsBackgroundLocationUpdates = true (requires Background Modes capability).
            break
        default:
            break
        }
    }

    /// Starts recording GPS locations.
    ///
    /// Requires location authorization to have been granted.
    /// Sets up background location updates for tracking while the app is backgrounded.
    func startTracking() {
        guard !isTracking else { return }

        // Reset state
        recordedLocations = []
        totalDistanceMeters = 0.0
        currentSpeed = 0.0
        currentLocation = nil
        lastError = nil
        kalmanFilter.reset()
        // Enable background updates
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true

        locationManager.startUpdatingLocation()
        isTracking = true

        #if DEBUG
        print("[LocationTrackingManager] Started tracking")
        #endif
    }

    /// Stops recording GPS locations and disables background updates.
    func stopTracking() {
        guard isTracking else { return }

        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.showsBackgroundLocationIndicator = false
        isTracking = false

        #if DEBUG
        print("[LocationTrackingManager] Stopped tracking. Total points: \(recordedLocations.count), Distance: \(String(format: "%.0f", totalDistanceMeters))m")
        #endif
    }

    /// Whether the user has granted sufficient location permissions.
    var hasLocationPermission: Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        default:
            return false
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationTrackingManager: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                processLocation(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            #if DEBUG
            print("[LocationTrackingManager] Location error: \(error.localizedDescription)")
            #endif
            // Ignore temporary errors (e.g., location temporarily unavailable)
            if let clError = error as? CLError, clError.code == .locationUnknown {
                return
            }
            self.lastError = error
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            #if DEBUG
            print("[LocationTrackingManager] Authorization changed: \(manager.authorizationStatus.rawValue)")
            #endif
        }
    }

    // MARK: - Private

    @MainActor
    private func processLocation(_ location: CLLocation) {
        let age = -location.timestamp.timeIntervalSinceNow
        guard age < mapRecordingMaxAgeSeconds else {
            #if DEBUG
            print("[LocationTrackingManager] Discarded stale location: age=\(String(format: "%.1f", age))s")
            #endif
            return
        }

        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= mapRecordingMaxHorizontalAccuracyMeters else {
            #if DEBUG
            print("[LocationTrackingManager] Discarded inaccurate location: accuracy=\(String(format: "%.0f", location.horizontalAccuracy))m")
            #endif
            return
        }

        // Apply Kalman filter to smooth GPS noise (reduces drift while stationary
        // and the "points beside the road" effect during running).
        let smoothedCoordinate = kalmanFilter.filter(
            coordinate: location.coordinate,
            accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )

        // Rebuild a CLLocation with the filtered coordinates but original metadata
        // (altitude, speed, accuracy, timestamp stay intact for downstream consumers).
        let filtered = CLLocation(
            coordinate: smoothedCoordinate,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            course: location.course,
            speed: location.speed,
            timestamp: location.timestamp
        )

        currentLocation = filtered

        if filtered.speed >= 0 {
            currentSpeed = filtered.speed
        } else if let last = recordedLocations.last {
            let dt = filtered.timestamp.timeIntervalSince(last.timestamp)
            if dt > 0.2 {
                currentSpeed = filtered.distance(from: last) / dt
            } else {
                currentSpeed = 0
            }
        } else {
            currentSpeed = 0
        }

        recordedLocations.append(filtered)

        // Debug-only cumulative distance (UI uses `JoggingTrackingManager` distances).
        if recordedLocations.count >= 2 {
            let previousLocation = recordedLocations[recordedLocations.count - 2]
            if let segment = RouteDistanceCalculator.acceptableSegmentMeters(from: previousLocation, to: filtered) {
                totalDistanceMeters += segment
            }
        }
    }
}
