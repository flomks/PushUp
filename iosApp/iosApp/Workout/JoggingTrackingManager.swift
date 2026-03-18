import Combine
import CoreLocation
import Foundation
import Shared

// MARK: - JoggingTrackingError

/// Errors that can occur during a jogging tracking session.
enum JoggingTrackingError: LocalizedError, Equatable, Sendable {
    case alreadyTracking
    case notTracking
    case locationPermissionDenied
    case sessionStartFailed(String)
    case sessionFinishFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyTracking:
            return "A jogging session is already in progress."
        case .notTracking:
            return "No jogging session is currently active."
        case .locationPermissionDenied:
            return "Location permission is required for jogging tracking."
        case .sessionStartFailed(let reason):
            return "Failed to start jogging session: \(reason)"
        case .sessionFinishFailed(let reason):
            return "Failed to finish jogging session: \(reason)"
        }
    }
}

// MARK: - JoggingTrackingManager

/// Connects the GPS location pipeline with the KMP business logic for jogging.
///
/// **Responsibilities**
/// - Owns and wires `LocationTrackingManager` for GPS tracking.
/// - On `startTracking()`: requests location permission, starts GPS,
///   and calls `StartJoggingUseCase` (KMP) to create a new session.
/// - Periodically records route points via `RecordRoutePointUseCase` (KMP).
/// - On `stopTracking()`: stops GPS and calls `FinishJoggingUseCase` (KMP).
/// - Publishes distance, duration, pace, speed, and route for SwiftUI consumers.
///
/// **Energy Efficiency**
/// - Route points are recorded at GPS update intervals (every ~5m of movement).
/// - KMP calls are batched -- route points are recorded asynchronously.
/// - The location manager handles background updates efficiently.
///
/// **Threading**
/// - All published properties and public methods are main-actor isolated.
/// - KMP use-case calls are dispatched to background Tasks.
@MainActor
final class JoggingTrackingManager: ObservableObject {

    // MARK: - Published State

    /// Whether a jogging session is currently active.
    @Published private(set) var isTracking: Bool = false

    /// Total distance covered in meters.
    @Published private(set) var distanceMeters: Double = 0.0

    /// Elapsed time of the current session in seconds.
    @Published private(set) var sessionDuration: TimeInterval = 0

    /// Current pace in seconds per kilometer, or nil if not enough data.
    @Published private(set) var currentPaceSecondsPerKm: Int?

    /// Current speed in m/s.
    @Published private(set) var currentSpeed: Double = 0.0

    /// Estimated calories burned.
    @Published private(set) var caloriesBurned: Int = 0

    /// The most recent error.
    @Published private(set) var lastError: JoggingTrackingError?

    /// All recorded locations for map display.
    @Published private(set) var routeLocations: [CLLocation] = []

    // MARK: - Private: Location & KMP

    let locationManager: LocationTrackingManager

    private let getCurrentUser: GetCurrentUserUseCase
    private let startJogging: StartJoggingUseCase
    private let recordRoutePoint: RecordRoutePointUseCase
    private let finishJogging: FinishJoggingUseCase

    private var activeSessionId: String?
    private var sessionStartDate: Date?
    private var sessionTimer: Timer?
    private var locationCancellable: AnyCancellable?
    private var startSessionTask: Task<Void, Never>?

    // MARK: - Init

    init(
        locationManager: LocationTrackingManager = LocationTrackingManager(),
        getCurrentUser: GetCurrentUserUseCase,
        startJogging: StartJoggingUseCase,
        recordRoutePoint: RecordRoutePointUseCase,
        finishJogging: FinishJoggingUseCase
    ) {
        self.locationManager = locationManager
        self.getCurrentUser = getCurrentUser
        self.startJogging = startJogging
        self.recordRoutePoint = recordRoutePoint
        self.finishJogging = finishJogging
    }

    /// Convenience initialiser that resolves use cases from the Koin DI graph.
    convenience init() {
        let helper = DIHelper.shared
        self.init(
            getCurrentUser: helper.getCurrentUserUseCase(),
            startJogging: helper.startJoggingUseCase(),
            recordRoutePoint: helper.recordRoutePointUseCase(),
            finishJogging: helper.finishJoggingUseCase()
        )
    }

    deinit {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    // MARK: - Public API

    /// Starts a jogging tracking session.
    func startTracking() {
        guard !isTracking else {
            #if DEBUG
            print("[JoggingTrackingManager] startTracking() called while already tracking -- ignored")
            #endif
            return
        }

        // Check location permission
        guard locationManager.hasLocationPermission else {
            locationManager.requestAuthorization()
            lastError = .locationPermissionDenied
            return
        }

        lastError = nil
        resetState()

        // Start GPS tracking
        locationManager.startTracking()

        // Observe location updates
        locationCancellable = locationManager.$recordedLocations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] locations in
                guard let self else { return }
                self.routeLocations = locations
                self.distanceMeters = self.locationManager.totalDistanceMeters
                self.currentSpeed = self.locationManager.currentSpeed

                // Record route point for the latest location
                if let latest = locations.last, let sessionId = self.activeSessionId {
                    self.recordLocationPoint(latest, sessionId: sessionId)
                }
            }

        isTracking = true
        sessionStartDate = Date()
        startSessionTimer()

        startSessionTask = Task {
            await startKMPSession()
        }
    }

    /// Stops the current jogging session.
    func stopTracking() {
        guard isTracking else {
            #if DEBUG
            print("[JoggingTrackingManager] stopTracking() called while not tracking -- ignored")
            #endif
            return
        }

        startSessionTask?.cancel()
        startSessionTask = nil

        let sessionId = activeSessionId

        // Stop GPS
        locationManager.stopTracking()
        locationCancellable?.cancel()
        locationCancellable = nil

        isTracking = false
        activeSessionId = nil
        stopSessionTimer()

        Task {
            await finishKMPSession(sessionId: sessionId)
        }
    }

    // MARK: - Private: State

    private func resetState() {
        distanceMeters = 0.0
        sessionDuration = 0
        currentPaceSecondsPerKm = nil
        currentSpeed = 0.0
        caloriesBurned = 0
        routeLocations = []
        activeSessionId = nil
    }

    // MARK: - Private: Session Timer

    private func startSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let start = self.sessionStartDate else { return }
                self.sessionDuration = Date().timeIntervalSince(start)

                // Update pace
                if self.distanceMeters >= 100 {
                    let paceSecondsPerKm = Int((self.sessionDuration / self.distanceMeters) * 1000.0)
                    self.currentPaceSecondsPerKm = paceSecondsPerKm
                }

                // Update calories (rough: 60 cal/km)
                self.caloriesBurned = Int(self.distanceMeters / 1000.0 * 60.0)
            }
        }
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        sessionDuration = 0
    }

    // MARK: - Private: KMP Calls

    private func startKMPSession() async {
        do {
            guard let user: User = try await withKMPSuspendOptional({ handler in
                self.getCurrentUser.invoke(completionHandler: handler)
            }) else {
                throw NSError(
                    domain: "JoggingTrackingManager",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "No authenticated user found. Please log in."]
                )
            }

            try Task.checkCancellation()

            let session = try await withKMPSuspend { handler in
                self.startJogging.invoke(userId: user.id, completionHandler: handler)
            } as Shared.JoggingSession

            guard !Task.isCancelled else { return }

            activeSessionId = session.id
            #if DEBUG
            print("[JoggingTrackingManager] KMP jogging session started: \(session.id)")
            #endif
        } catch is CancellationError {
            #if DEBUG
            print("[JoggingTrackingManager] startKMPSession cancelled")
            #endif
        } catch {
            #if DEBUG
            print("[JoggingTrackingManager] Failed to start KMP session: \(error)")
            #endif
            locationManager.stopTracking()
            locationCancellable?.cancel()
            locationCancellable = nil
            isTracking = false
            stopSessionTimer()
            lastError = .sessionStartFailed(error.localizedDescription)
        }
    }

    /// Records a single GPS location as a route point in the KMP session.
    private func recordLocationPoint(_ location: CLLocation, sessionId: String) {
        let useCase = self.recordRoutePoint
        let distance = self.distanceMeters

        Task {
            do {
                _ = try await withKMPSuspend { handler in
                    useCase.invoke(
                        sessionId: sessionId,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        altitude: location.altitude >= 0 ? KotlinDouble(value: location.altitude) : nil,
                        speed: location.speed >= 0 ? KotlinDouble(value: location.speed) : nil,
                        horizontalAccuracy: location.horizontalAccuracy >= 0 ? KotlinDouble(value: location.horizontalAccuracy) : nil,
                        distanceFromStart: distance,
                        completionHandler: handler
                    )
                } as Shared.RoutePoint
            } catch {
                // Non-fatal: route point recording failure does not stop the session
                #if DEBUG
                print("[JoggingTrackingManager] Failed to record route point: \(error)")
                #endif
            }
        }
    }

    private func finishKMPSession(sessionId: String?) async {
        guard let sessionId else {
            #if DEBUG
            print("[JoggingTrackingManager] finishKMPSession: no active session -- skipped")
            #endif
            return
        }

        do {
            let summary = try await withKMPSuspend { handler in
                self.finishJogging.invoke(sessionId: sessionId, completionHandler: handler)
            } as Shared.JoggingSummary
            #if DEBUG
            print(
                "[JoggingTrackingManager] Jogging session finished." +
                " distance=\(String(format: "%.0f", summary.session.distanceMeters))m" +
                " credits=\(summary.earnedCredits)" +
                " xp=\(summary.earnedXp)"
            )
            #endif

            // Trigger post-workout sync
            SyncBridge.shared.syncAfterWorkout(
                onSuccess: {
                    #if DEBUG
                    print("[JoggingTrackingManager] Post-jogging sync completed.")
                    #endif
                },
                onError: { errorMessage in
                    #if DEBUG
                    print("[JoggingTrackingManager] Post-jogging sync failed: \(errorMessage)")
                    #endif
                }
            )
        } catch {
            #if DEBUG
            print("[JoggingTrackingManager] Failed to finish KMP session: \(error)")
            #endif
            lastError = .sessionFinishFailed(error.localizedDescription)
        }
    }
}

// MARK: - KMP Coroutine Bridge (reused from PushUpTrackingManager)

private func withKMPSuspend<T>(
    _ body: @escaping (@escaping (T?, Error?) -> Void) -> Void
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let lock = NSLock()
        var hasResumed = false

        body { result, error in
            lock.lock()
            guard !hasResumed else {
                lock.unlock()
                return
            }
            hasResumed = true
            lock.unlock()

            if let error {
                continuation.resume(throwing: error)
            } else if let result {
                continuation.resume(returning: result)
            } else {
                continuation.resume(
                    throwing: NSError(
                        domain: "JoggingTrackingManager.KMPBridge",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "KMP suspend function returned nil result with no error"]
                    )
                )
            }
        }
    }
}

private func withKMPSuspendOptional<T>(
    _ body: @escaping (@escaping (T?, Error?) -> Void) -> Void
) async throws -> T? {
    try await withCheckedThrowingContinuation { continuation in
        let lock = NSLock()
        var hasResumed = false

        body { result, error in
            lock.lock()
            guard !hasResumed else {
                lock.unlock()
                return
            }
            hasResumed = true
            lock.unlock()

            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: result)
            }
        }
    }
}
