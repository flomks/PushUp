import CoreLocation

/// Lightweight display-only smoothing for GPS route polylines.
///
/// Uses a single pass weighted 3-point filter:
/// smoothed[i] = 0.25 * prev + 0.5 * current + 0.25 * next
/// Start/end points are preserved to keep route endpoints exact.
enum RouteSmoothing {

    static func smoothCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 3 else { return coordinates }

        var smoothed = coordinates
        for index in 1..<(coordinates.count - 1) {
            let previous = coordinates[index - 1]
            let current = coordinates[index]
            let next = coordinates[index + 1]

            smoothed[index] = CLLocationCoordinate2D(
                latitude: (previous.latitude * 0.25) + (current.latitude * 0.5) + (next.latitude * 0.25),
                longitude: (previous.longitude * 0.25) + (current.longitude * 0.5) + (next.longitude * 0.25)
            )
        }

        return smoothed
    }
}
