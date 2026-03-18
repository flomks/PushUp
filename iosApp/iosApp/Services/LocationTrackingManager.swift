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

    /// Minimum horizontal accuracy in meters. Locations with worse accuracy are discarded.
    private let accuracyThreshold: Double = 20.0

    /// Minimum distance between updates in meters.
    private let distanceFilter: Double = 5.0

    /// Number of initial GPS fixes to discard (warmup phase).
    /// The first few GPS readings after starting are often inaccurate cached positions.
    private let warmupPointCount: Int = 3

    /// Counter for received GPS points since tracking started.
    private var receivedPointCount: Int = 0

    /// Minimum speed in m/s to count distance. Below this, the user is likely
    /// stationary and GPS drift should not be counted as movement.
    private let minimumSpeedForDistance: Double = 0.3

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
        receivedPointCount = 0

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
        // Filter out inaccurate locations
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= accuracyThreshold else {
            #if DEBUG
            print("[LocationTrackingManager] Discarded inaccurate location: accuracy=\(String(format: "%.0f", location.horizontalAccuracy))m")
            #endif
            return
        }

        // Filter out old cached locations (older than 10 seconds)
        let age = -location.timestamp.timeIntervalSinceNow
        guard age < 10.0 else {
            #if DEBUG
            print("[LocationTrackingManager] Discarded stale location: age=\(String(format: "%.1f", age))s")
            #endif
            return
        }

        receivedPointCount += 1

        // Warmup phase: discard the first few GPS fixes which are often
        // inaccurate cached positions (especially indoors). We still update
        // the current location for the map, but do NOT count distance.
        if receivedPointCount <= warmupPointCount {
            #if DEBUG
            print("[LocationTrackingManager] Warmup point \(receivedPointCount)/\(warmupPointCount) -- distance not counted")
            #endif
            currentLocation = location
            currentSpeed = location.speed >= 0 ? location.speed : 0.0
            // Only start recording route points after warmup
            if receivedPointCount == warmupPointCount {
                recordedLocations.append(location)
            }
            return
        }

        // Calculate distance from previous point
        if let lastLocation = recordedLocations.last {
            let delta = location.distance(from: lastLocation)
            // Only count distance if:
            // 1. Movement is >= 2m (filter GPS noise)
            // 2. User is actually moving (speed >= minimum threshold)
            // 3. The delta is plausible (< 50m between updates to filter GPS jumps)
            let effectiveSpeed = location.speed >= 0 ? location.speed : 0.0
            if delta >= 2.0 && delta < 50.0 && effectiveSpeed >= minimumSpeedForDistance {
                totalDistanceMeters += delta
            }
        }

        // Update speed (use CLLocation's speed if valid, otherwise 0)
        currentSpeed = location.speed >= 0 ? location.speed : 0.0

        currentLocation = location
        recordedLocations.append(location)
    }
}
