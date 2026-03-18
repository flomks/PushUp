import Combine
import CoreLocation
import Foundation
import UIKit

// MARK: - JoggingPhase

/// The current phase of the jogging workout flow.
enum JoggingPhase: Equatable {
    case idle
    case active
    case confirmingStop
    case finished
}

// MARK: - JoggingViewModel

/// View model for the jogging workout screen.
///
/// Wraps `JoggingTrackingManager` with UI-specific state management:
/// - Workout phases (idle, active, confirming stop, finished)
/// - Idle timer management
/// - Haptic feedback
/// - Formatted display values
@MainActor
final class JoggingViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var phase: JoggingPhase = .idle
    @Published private(set) var distanceMeters: Double = 0.0
    @Published private(set) var sessionDuration: TimeInterval = 0
    @Published private(set) var currentPaceSecondsPerKm: Int?
    @Published private(set) var currentSpeed: Double = 0.0
    @Published private(set) var caloriesBurned: Int = 0
    @Published private(set) var routeLocations: [CLLocation] = []
    @Published private(set) var lastError: JoggingTrackingError?
    @Published private(set) var earnedMinutes: Int = 0

    // MARK: - Private

    let trackingManager: JoggingTrackingManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    /// Creates a view model with the given tracking manager.
    /// Must be called from the main actor since JoggingTrackingManager is @MainActor-isolated.
    init(trackingManager: JoggingTrackingManager) {
        self.trackingManager = trackingManager
        observeTrackingManager()
    }

    /// Convenience initialiser that creates a default tracking manager.
    /// Must be called from the main actor.
    convenience init() {
        self.init(trackingManager: JoggingTrackingManager())
    }

    // MARK: - Public API

    /// Starts the jogging workout.
    func startWorkout() {
        phase = .active
        UIApplication.shared.isIdleTimerDisabled = true
        trackingManager.startTracking()
    }

    /// Requests confirmation before stopping.
    func requestStop() {
        phase = .confirmingStop
    }

    /// Cancels the stop request and resumes the workout.
    func cancelStop() {
        phase = .active
    }

    /// Confirms stopping the workout.
    func confirmStop() {
        trackingManager.stopTracking()
        UIApplication.shared.isIdleTimerDisabled = false

        // Calculate earned minutes
        let distanceKm = distanceMeters / 1000.0
        earnedMinutes = distanceMeters >= 100 ? max(1, Int(distanceKm)) : 0

        phase = .finished
    }

    /// Requests location permission.
    func requestLocationPermission() {
        trackingManager.locationManager.requestAuthorization()
    }

    // MARK: - Formatted Values

    /// Distance formatted as "X.XX km" or "XXX m".
    var formattedDistance: String {
        if distanceMeters >= 1000 {
            return String(format: "%.2f km", distanceMeters / 1000.0)
        } else {
            return String(format: "%.0f m", distanceMeters)
        }
    }

    /// Duration formatted as "MM:SS" or "H:MM:SS".
    var formattedDuration: String {
        let totalSeconds = Int(sessionDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// Pace formatted as "M:SS /km" or "--:--".
    var formattedPace: String {
        guard let pace = currentPaceSecondsPerKm, pace > 0 else {
            return "--:-- /km"
        }
        let minutes = pace / 60
        let seconds = pace % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    /// Speed formatted as "X.X km/h".
    var formattedSpeed: String {
        let kmh = currentSpeed * 3.6
        return String(format: "%.1f km/h", kmh)
    }

    /// Whether the user has location permission.
    var hasLocationPermission: Bool {
        trackingManager.locationManager.hasLocationPermission
    }

    // MARK: - Private

    private func observeTrackingManager() {
        trackingManager.$distanceMeters
            .receive(on: DispatchQueue.main)
            .assign(to: &$distanceMeters)

        trackingManager.$sessionDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$sessionDuration)

        trackingManager.$currentPaceSecondsPerKm
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentPaceSecondsPerKm)

        trackingManager.$currentSpeed
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentSpeed)

        trackingManager.$caloriesBurned
            .receive(on: DispatchQueue.main)
            .assign(to: &$caloriesBurned)

        trackingManager.$routeLocations
            .receive(on: DispatchQueue.main)
            .assign(to: &$routeLocations)

        trackingManager.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastError)
    }
}
