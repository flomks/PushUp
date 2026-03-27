import Combine
import CoreLocation
import Foundation
import Shared
import UIKit

// MARK: - JoggingPhase

/// The current phase of the jogging workout flow.
enum JoggingPhase: Equatable {
    case idle
    case active
    case confirmingStop
    case finished
}

enum RunParticipantStatus: String {
    case running
    case invited
}

struct RunParticipant: Identifiable, Equatable {
    let id: String
    let displayName: String
    let username: String?
    var status: RunParticipantStatus

    var initials: String {
        let source = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "?" }
        let parts = source
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(source.prefix(2)).uppercased()
    }
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
    @Published private(set) var activeDuration: TimeInterval = 0
    @Published private(set) var pauseDuration: TimeInterval = 0
    @Published private(set) var currentPaceSecondsPerKm: Int?
    @Published private(set) var currentSpeed: Double = 0.0
    @Published private(set) var caloriesBurned: Int = 0
    @Published private(set) var routeLocations: [CLLocation] = []
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var activeDistanceMeters: Double = 0.0
    @Published private(set) var pauseDistanceMeters: Double = 0.0
    @Published private(set) var lastError: JoggingTrackingError?
    @Published private(set) var earnedMinutes: Int = 0
    @Published private(set) var dashboard: RunningDashboardData = .empty
    @Published private(set) var runParticipants: [RunParticipant] = []
    @Published private(set) var inviteableFriends: [RunParticipant] = []
    @Published private(set) var isLoadingRunSocialData: Bool = false

    // MARK: - Private

    let trackingManager: JoggingTrackingManager
    private var cancellables = Set<AnyCancellable>()
    private var joggingObservationJob: Kotlinx_coroutines_coreJob?

    // MARK: - Init

    /// Creates a view model with the given tracking manager.
    /// Must be called from the main actor since JoggingTrackingManager is @MainActor-isolated.
    init(trackingManager: JoggingTrackingManager) {
        self.trackingManager = trackingManager
        observeTrackingManager()
        Task { await startDashboardObserving() }
        Task { await loadRunSocialData() }
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

    func pauseWorkout() {
        trackingManager.pauseTracking()
    }

    func resumeWorkout() {
        trackingManager.resumeTracking()
    }

    func loadRunSocialData() async {
        isLoadingRunSocialData = true

        if let currentUser = await AuthService.shared.getCurrentUser() {
            let safeDisplayName = currentUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let me = RunParticipant(
                id: currentUser.id,
                displayName: safeDisplayName.isEmpty ? "You" : safeDisplayName,
                username: currentUser.username,
                status: .running
            )
            if !runParticipants.contains(where: { $0.id == me.id }) {
                runParticipants = [me]
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            FriendsBridge.shared.getFriends(
                onResult: { [weak self] friends in
                    guard let self else { continuation.resume(); return }
                    let mapped = friends.map {
                        RunParticipant(
                            id: $0.id,
                            displayName: ($0.displayName?.isEmpty == false ? $0.displayName! : ($0.username ?? "Unknown")),
                            username: $0.username,
                            status: .invited
                        )
                    }
                    self.inviteableFriends = mapped
                    self.isLoadingRunSocialData = false
                    continuation.resume()
                },
                onError: { [weak self] _ in
                    self?.inviteableFriends = []
                    self?.isLoadingRunSocialData = false
                    continuation.resume()
                }
            )
        }
    }

    func inviteFriendToRun(_ friendId: String) {
        guard let idx = inviteableFriends.firstIndex(where: { $0.id == friendId }) else { return }
        var invited = inviteableFriends.remove(at: idx)
        invited.status = .invited
        if !runParticipants.contains(where: { $0.id == invited.id }) {
            runParticipants.append(invited)
        }
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
        let totalSeconds = Int(activeDuration)
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

    private func startDashboardObserving() async {
        guard joggingObservationJob == nil else { return }
        guard let user = await AuthService.shared.getCurrentUser() else {
            dashboard = .empty
            return
        }

        joggingObservationJob = DataBridge.shared.observeJoggingSessions(userId: user.id) { [weak self] sessions in
            guard let self else { return }
            let completed = sessions.filter { $0.endedAt != nil }
            self.dashboard = RunningDashboardData.build(from: completed)
        }
    }

    private func observeTrackingManager() {
        trackingManager.$distanceMeters
            .receive(on: DispatchQueue.main)
            .assign(to: &$distanceMeters)

        trackingManager.$sessionDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$sessionDuration)
        trackingManager.$activeDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeDuration)
        trackingManager.$pauseDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$pauseDuration)

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
        trackingManager.$isPaused
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPaused)
        trackingManager.$activeDistanceMeters
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeDistanceMeters)
        trackingManager.$pauseDistanceMeters
            .receive(on: DispatchQueue.main)
            .assign(to: &$pauseDistanceMeters)

        trackingManager.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastError)
    }

    deinit {
        joggingObservationJob?.cancel(cause: nil)
    }
}

// MARK: - RunningDashboardData

struct RunningDashboardData {
    let weekDistanceMeters: Double
    let weekRuns: Int
    let weekEarnedMinutes: Int
    let averagePaceSecondsPerKm: Int?
    let bestDistanceMeters: Double
    let longestRunDurationSeconds: Int
    let recentRuns: [RecentRun]

    static let empty = RunningDashboardData(
        weekDistanceMeters: 0,
        weekRuns: 0,
        weekEarnedMinutes: 0,
        averagePaceSecondsPerKm: nil,
        bestDistanceMeters: 0,
        longestRunDurationSeconds: 0,
        recentRuns: []
    )

    struct RecentRun: Identifiable {
        let id: String
        let date: Date
        let distanceMeters: Double
        let durationSeconds: Int
        let earnedMinutes: Int
        let avgPaceSecondsPerKm: Int?
    }

    static func build(from sessions: [Shared.JoggingSession]) -> RunningDashboardData {
        guard !sessions.isEmpty else { return .empty }

        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = (weekday + 5) % 7
        let weekStart = calendar.date(
            byAdding: .day,
            value: -mondayOffset,
            to: calendar.startOfDay(for: today)
        ) ?? today

        let weekSessions = sessions.filter { session in
            let date = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
            return date >= weekStart
        }

        let weekDistance = weekSessions.reduce(0.0) { $0 + $1.distanceMeters }
        let weekEarned = weekSessions.reduce(0) { $0 + Int($1.earnedTimeCreditSeconds / 60) }
        let paceValues = weekSessions.compactMap { $0.avgPaceSecondsPerKm?.intValue }.filter { $0 > 0 }
        let avgPace = paceValues.isEmpty ? nil : (paceValues.reduce(0, +) / paceValues.count)
        let bestDistance = sessions.map(\.distanceMeters).max() ?? 0
        let longestDuration = sessions.map { Int($0.durationSeconds) }.max() ?? 0

        let recent = sessions
            .sorted(by: { $0.startedAt.epochSeconds > $1.startedAt.epochSeconds })
            .prefix(5)
            .map { session in
                let runDate = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
                return RecentRun(
                    id: session.id,
                    date: runDate,
                    distanceMeters: session.distanceMeters,
                    durationSeconds: Int(session.durationSeconds),
                    earnedMinutes: Int(session.earnedTimeCreditSeconds / 60),
                    avgPaceSecondsPerKm: session.avgPaceSecondsPerKm?.intValue
                )
            }

        return RunningDashboardData(
            weekDistanceMeters: weekDistance,
            weekRuns: weekSessions.count,
            weekEarnedMinutes: weekEarned,
            averagePaceSecondsPerKm: avgPace,
            bestDistanceMeters: bestDistance,
            longestRunDurationSeconds: longestDuration,
            recentRuns: Array(recent)
        )
    }
}
