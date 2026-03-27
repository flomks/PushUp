import CoreLocation
import Foundation

/// Distance accumulation between GPS fixes — inspired by common OSS tracker patterns
/// (e.g. OpenTracks-style: sum great-circle segments, reject obvious outliers).
///
/// - GPS works fully **offline**; this is pure geometry + sanity checks.
/// - Does not depend on network or `CLLocation.speed` (often `-1` on iOS).
enum RouteDistanceCalculator {

    /// Minimum segment length to count (filters sub-meter jitter).
    static let minimumSegmentMeters: Double = 1.5

    /// Reject segments that imply faster than this (GPS jump / teleport). ~90 km/h.
    static let maximumPlausibleSpeedMetersPerSecond: Double = 25.0

    /// Reject if horizontal accuracy is worse than this (meters). `-1` = invalid.
    static let maximumHorizontalAccuracyMeters: Double = 75.0

    /// Ignore fixes older than this (stale cached locations).
    static let maximumLocationAgeSeconds: TimeInterval = 45.0

    /// Returns distance to add for this segment, or `nil` if the segment should be ignored.
    static func acceptableSegmentMeters(from previous: CLLocation, to latest: CLLocation) -> Double? {
        guard isFixUsable(latest), isFixUsable(previous) else { return nil }

        let delta = max(0, latest.distance(from: previous))
        guard delta >= minimumSegmentMeters else { return nil }

        let dt = latest.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0 else { return nil }

        let impliedSpeed = delta / dt
        guard impliedSpeed <= maximumPlausibleSpeedMetersPerSecond else { return nil }

        return delta
    }

    static func isFixUsable(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0 else { return false }
        guard location.horizontalAccuracy <= maximumHorizontalAccuracyMeters else { return false }
        let age = -location.timestamp.timeIntervalSinceNow
        return age < maximumLocationAgeSeconds
    }
}
