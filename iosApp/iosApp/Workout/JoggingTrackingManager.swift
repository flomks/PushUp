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
    case alreadyPaused
    case notPaused
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
        case .alreadyPaused:
            return "The run is already paused."
        case .notPaused:
            return "The run is not paused."
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
    @Published private(set) var isPaused: Bool = false

    /// Total distance covered in meters.
    @Published private(set) var distanceMeters: Double = 0.0
    @Published private(set) var activeDistanceMeters: Double = 0.0
    @Published private(set) var pauseDistanceMeters: Double = 0.0

    /// Elapsed time of the current session in seconds.
    @Published private(set) var sessionDuration: TimeInterval = 0
    @Published private(set) var activeDuration: TimeInterval = 0
    @Published private(set) var pauseDuration: TimeInterval = 0

    /// Current pace in seconds per kilometer, or nil if not enough data.
    @Published private(set) var currentPaceSecondsPerKm: Int?

    /// Current speed in m/s.
    @Published private(set) var currentSpeed: Double = 0.0

    /// Estimated calories burned.
    @Published private(set) var caloriesBurned: Int = 0

    /// The most recent error.
    @Published private(set) var lastError: JoggingTrackingError?
    @Published private(set) var lastFinishedSummary: Shared.JoggingSummary?

    /// All recorded locations for map display.
    @Published private(set) var routeLocations: [CLLocation] = []

    // MARK: - Private: Location & KMP

    let locationManager: LocationTrackingManager

    private let getCurrentUser: GetCurrentUserUseCase
    private let startJogging: StartJoggingUseCase
    private let recordRoutePoint: RecordRoutePointUseCase
    private let finishJogging: FinishJoggingUseCase
    private let saveJoggingSegments: SaveJoggingSegmentsUseCase
    private let saveJoggingPlaybackEntries: SaveJoggingPlaybackEntriesUseCase
    private let liveSessionManager: LiveJoggingSessionManager

    // MARK: - Published: Anti-Cheat

    /// True when a vehicle (car, bus, train) is detected during the session.
    /// Distance is not counted while this is true.
    @Published private(set) var isVehicleDetected: Bool = false

    // MARK: - Private: Session State

    private var activeSessionId: String?
    private var activeLiveRunSessionId: String?
    private var activeUserId: String?
    private var sessionStartDate: Date?
    private var sessionTimer: Timer?
    private var locationCancellable: AnyCancellable?
    private var vehicleDetectorCancellable: AnyCancellable?
    private var startSessionTask: Task<Void, Never>?
    private var lastProcessedLocation: CLLocation?
    private var routeDistanceMeters: Double = 0.0
    private var segmentEvents: [LocalJoggingSegment] = []
    private var playbackEntries: [LocalJoggingPlaybackEntry] = []
    private var activePlaybackEntry: ActiveJoggingPlaybackEntry?
    private var currentSegmentStartDate: Date?
    private var currentSegmentDistanceStart: Double = 0
    private var pauseStartedAt: Date?
    private var accumulatedPauseDuration: TimeInterval = 0

    // MARK: - Private: Vehicle / Anti-Cheat

    private let vehicleDetector = VehicleMotionDetector()

    /// Rolling window of (timestamp, speed m/s) observations for sustained-speed detection.
    private var recentSpeedObservations: [(timestamp: Date, speed: Double)] = []

    private let speedValueStaleAfterSeconds: TimeInterval = 2.5
    private let stationarySpeedThresholdMetersPerSecond: Double = 0.18
    private let minimumPlaybackEntryDurationSeconds: TimeInterval = 3.0

    // MARK: - Init

    init(
        locationManager: LocationTrackingManager,
        getCurrentUser: GetCurrentUserUseCase,
        startJogging: StartJoggingUseCase,
        recordRoutePoint: RecordRoutePointUseCase,
        finishJogging: FinishJoggingUseCase,
        saveJoggingSegments: SaveJoggingSegmentsUseCase,
        saveJoggingPlaybackEntries: SaveJoggingPlaybackEntriesUseCase,
        liveSessionManager: LiveJoggingSessionManager
    ) {
        self.locationManager = locationManager
        self.getCurrentUser = getCurrentUser
        self.startJogging = startJogging
        self.recordRoutePoint = recordRoutePoint
        self.finishJogging = finishJogging
        self.saveJoggingSegments = saveJoggingSegments
        self.saveJoggingPlaybackEntries = saveJoggingPlaybackEntries
        self.liveSessionManager = liveSessionManager
    }

    /// Convenience initialiser that resolves use cases from the Koin DI graph.
    /// Must be called from the main actor since LocationTrackingManager is @MainActor-isolated.
    convenience init() {
        let helper = DIHelper.shared
        self.init(
            locationManager: LocationTrackingManager(),
            getCurrentUser: helper.getCurrentUserUseCase(),
            startJogging: helper.startJoggingUseCase(),
            recordRoutePoint: helper.recordRoutePointUseCase(),
            finishJogging: helper.finishJoggingUseCase(),
            saveJoggingSegments: helper.saveJoggingSegmentsUseCase(),
            saveJoggingPlaybackEntries: helper.saveJoggingPlaybackEntriesUseCase(),
            liveSessionManager: helper.liveJoggingSessionManager()
        )
    }

    deinit {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    // MARK: - Public API

    /// Starts a jogging tracking session.
    func startTracking(liveRunSessionId: String? = nil) {
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
        activeLiveRunSessionId = liveRunSessionId

        // Start GPS tracking
        locationManager.startTracking()

        // Observe location updates
        locationCancellable = locationManager.$recordedLocations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] locations in
                guard let self else { return }
                self.routeLocations = locations
                self.currentSpeed = self.displaySpeedMetersPerSecond(latest: locations.last, now: Date())
                self.consumeLocations(locations)

                // Record route point for the latest location
                if let latest = locations.last, let sessionId = self.activeSessionId {
                    self.recordLocationPoint(
                        latest,
                        sessionId: sessionId,
                        totalDistance: self.activeDistanceMeters,
                        activeDurationSeconds: Int64(self.activeDuration)
                    )
                }
            }

        isTracking = true
        isPaused = false
        sessionStartDate = Date()
        currentSegmentStartDate = sessionStartDate
        currentSegmentDistanceStart = 0
        startSessionTimer()

        // Start vehicle / anti-cheat detection
        vehicleDetector.startMonitoring()
        vehicleDetectorCancellable = vehicleDetector.$isInVehicle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] inVehicle in
                guard let self else { return }
                // CoreMotion signals automotive → update immediately even without new GPS.
                // Clearing waits for the next GPS cycle so sustained-speed is re-evaluated.
                if inVehicle {
                    self.isVehicleDetected = true
                } else {
                    self.isVehicleDetected = self.isSustainedVehicleSpeed()
                }
            }

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

        // Stop live session streaming (flushes remaining points, removes presence)
        liveSessionManager.stop()

        // Stop vehicle detection
        vehicleDetector.stopMonitoring()
        vehicleDetectorCancellable?.cancel()
        vehicleDetectorCancellable = nil

        // Stop GPS
        locationManager.stopTracking()
        locationCancellable?.cancel()
        locationCancellable = nil

        let endTime = Date()
        refreshSessionDurations(at: endTime)
        endCurrentSegment(at: endTime)
        endActivePlaybackEntry(at: endTime)

        isTracking = false
        isPaused = false
        activeSessionId = nil
        activeLiveRunSessionId = nil
        activeUserId = nil
        stopSessionTimer()

        Task {
            await persistSegmentsIfPossible(sessionId: sessionId)
            await persistPlaybackEntriesIfPossible(sessionId: sessionId)
            await finishKMPSession(sessionId: sessionId)
        }
    }

    func pauseTracking() {
        guard isTracking else { return }
        guard !isPaused else {
            lastError = .alreadyPaused
            return
        }
        let now = Date()
        // Close the current RUN segment before switching state.
        finalizeSegment(at: now, isPauseSegment: false)

        isPaused = true
        pauseStartedAt = now
        currentSegmentStartDate = now
        currentSegmentDistanceStart = routeDistanceMeters
    }

    func resumeTracking() {
        guard isTracking else { return }
        guard isPaused else {
            lastError = .notPaused
            return
        }
        let resumeTime = Date()
        // Close the PAUSE segment.
        finalizeSegment(at: resumeTime, isPauseSegment: true)

        if let pauseStartedAt {
            accumulatedPauseDuration += max(0, resumeTime.timeIntervalSince(pauseStartedAt))
        }

        isPaused = false
        pauseStartedAt = nil
        currentSegmentStartDate = resumeTime
        currentSegmentDistanceStart = routeDistanceMeters
    }

    func updatePlaybackState(
        source: String = "spotify",
        trackTitle: String?,
        artistName: String?,
        spotifyTrackUri: String? = nil,
        isPlaying: Bool
    ) {
        guard isTracking else { return }

        let now = Date()
        let normalizedTitle = trackTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = artistName?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isPlaying, let normalizedTitle, !normalizedTitle.isEmpty else {
            endActivePlaybackEntry(at: now)
            return
        }

        if let activePlaybackEntry,
           activePlaybackEntry.source == source,
           activePlaybackEntry.trackTitle == normalizedTitle,
           activePlaybackEntry.artistName == normalizedArtist {
            return
        }

        endActivePlaybackEntry(at: now)
        activePlaybackEntry = ActiveJoggingPlaybackEntry(
            id: UUID().uuidString,
            source: source,
            trackTitle: normalizedTitle,
            artistName: normalizedArtist?.isEmpty == false ? normalizedArtist : nil,
            spotifyTrackUri: spotifyTrackUri?.trimmingCharacters(in: .whitespacesAndNewlines),
            startedAt: now,
            startDistanceMeters: activeDistanceMeters,
            startActiveDurationSeconds: Int64(activeDuration)
        )
    }

    // MARK: - Private: State

    private func resetState() {
        distanceMeters = 0.0
        activeDistanceMeters = 0.0
        pauseDistanceMeters = 0.0
        sessionDuration = 0
        activeDuration = 0
        pauseDuration = 0
        currentPaceSecondsPerKm = nil
        currentSpeed = 0.0
        caloriesBurned = 0
        routeLocations = []
        lastFinishedSummary = nil
        activeSessionId = nil
        activeLiveRunSessionId = nil
        routeDistanceMeters = 0
        isPaused = false
        pauseStartedAt = nil
        accumulatedPauseDuration = 0
        lastProcessedLocation = nil
        segmentEvents = []
        playbackEntries = []
        activePlaybackEntry = nil
        currentSegmentStartDate = nil
        currentSegmentDistanceStart = 0
        isVehicleDetected = false
        recentSpeedObservations = []
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
                let now = Date()
                self.refreshSessionDurations(at: now)

                // Keep speed responsive even when GPS updates pause or drift values linger.
                self.currentSpeed = self.displaySpeedMetersPerSecond(latest: self.routeLocations.last, now: now)

                // Update pace
                if self.activeDistanceMeters >= 100, self.activeDuration > 0 {
                    let paceSecondsPerKm = Int((self.activeDuration / self.activeDistanceMeters) * 1000.0)
                    self.currentPaceSecondsPerKm = paceSecondsPerKm
                } else {
                    self.currentPaceSecondsPerKm = nil
                }

                // Update calories (rough: 60 cal/km)
                self.caloriesBurned = Int(self.activeDistanceMeters / 1000.0 * 60.0)
            }
        }
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        sessionDuration = 0
        activeDuration = 0
        pauseDuration = 0
    }

    private func refreshSessionDurations(at now: Date) {
        guard let start = sessionStartDate else {
            sessionDuration = 0
            activeDuration = 0
            pauseDuration = 0
            return
        }
        sessionDuration = now.timeIntervalSince(start)
        pauseDuration = currentPauseDuration(at: now)
        activeDuration = max(0, sessionDuration - pauseDuration)
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
                self.startJogging.invoke(
                    userId: user.id,
                    liveRunSessionId: self.activeLiveRunSessionId,
                    completionHandler: handler
                )
            } as Shared.JoggingSession

            guard !Task.isCancelled else { return }

            activeSessionId = session.id
            activeUserId = user.id

            // Start live session streaming (batched route uploads + presence)
            let startInstant = Kotlinx_datetimeInstant.companion.fromEpochMilliseconds(
                epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1000.0)
            )
            liveSessionManager.start(userId: user.id, sessionId: session.id, startedAt: startInstant)

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
    private func recordLocationPoint(
        _ location: CLLocation,
        sessionId: String,
        totalDistance: Double,
        activeDurationSeconds: Int64
    ) {
        let useCase = self.recordRoutePoint
        // Convert CLLocation timestamp to Kotlinx Instant for the KMP use case.
        // Kotlin/Native does not export default parameter values to Swift,
        // so we must pass the timestamp explicitly.
        let timestamp = Kotlinx_datetimeInstant.companion.fromEpochMilliseconds(
            epochMilliseconds: Int64(location.timestamp.timeIntervalSince1970 * 1000.0)
        )

        Task {
            do {
                let routePoint = try await withKMPSuspend { handler in
                    useCase.invoke(
                        sessionId: sessionId,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        altitude: location.altitude >= 0 ? KotlinDouble(value: location.altitude) : nil,
                        speed: location.speed >= 0 ? KotlinDouble(value: location.speed) : nil,
                        horizontalAccuracy: location.horizontalAccuracy >= 0 ? KotlinDouble(value: location.horizontalAccuracy) : nil,
                        distanceFromStart: totalDistance,
                        activeDurationSecondsOverride: KotlinLong(value: activeDurationSeconds),
                        timestamp: timestamp,
                        completionHandler: handler
                    )
                } as Shared.RoutePoint

                // Enqueue for batched upload to Supabase (fire-and-forget)
                liveSessionManager.enqueueRoutePoint(point: routePoint)
            } catch {
                // Non-fatal: route point recording failure does not stop the session
                #if DEBUG
                print("[JoggingTrackingManager] Failed to record route point: \(error)")
                #endif
            }
        }
    }

    /// Core Location can deliver **multiple** fixes per `didUpdateLocations` callback.
    /// Processing only `locations.last` skips intermediate points and undercounts distance.
    private func consumeLocations(_ locations: [CLLocation]) {
        guard !locations.isEmpty else { return }

        let startIndex: Int
        if let anchor = lastProcessedLocation {
            // Prefer matching the previous anchor in the array (stable across batch deliveries).
            if let idx = locations.firstIndex(where: { $0.distance(from: anchor) < 1.0 }) {
                startIndex = idx + 1
            } else {
                startIndex = locations.firstIndex(where: { $0.timestamp > anchor.timestamp }) ?? locations.count
            }
        } else {
            startIndex = 0
        }

        guard startIndex < locations.count else {
            distanceMeters = activeDistanceMeters
            return
        }

        for i in startIndex..<locations.count {
            consumeSingleLocation(locations[i])
        }
    }

    private func consumeSingleLocation(_ latest: CLLocation) {
        guard RouteDistanceCalculator.isFixUsable(latest) else {
            distanceMeters = activeDistanceMeters
            return
        }

        guard let previous = lastProcessedLocation else {
            lastProcessedLocation = latest
            distanceMeters = activeDistanceMeters
            return
        }

        guard RouteDistanceCalculator.isFixUsable(previous) else {
            lastProcessedLocation = latest
            distanceMeters = activeDistanceMeters
            return
        }

        // Compute instantaneous speed between fixes and update rolling window.
        let dt = latest.timestamp.timeIntervalSince(previous.timestamp)
        if dt > 0 {
            let d = latest.distance(from: previous)
            updateSpeedWindow(timestamp: latest.timestamp, speed: d / dt)
        }

        // Skip distance accumulation while a vehicle is detected.
        // The GPS anchor still advances so the route polyline stays correct.
        guard !isVehicleDetected else {
            lastProcessedLocation = latest
            return
        }

        guard let delta = RouteDistanceCalculator.acceptableSegmentMeters(from: previous, to: latest) else {
            distanceMeters = activeDistanceMeters
            lastProcessedLocation = latest
            return
        }

        routeDistanceMeters += delta
        if isPaused {
            pauseDistanceMeters += delta
        } else {
            activeDistanceMeters += delta
        }
        distanceMeters = activeDistanceMeters
        lastProcessedLocation = latest
    }

    // MARK: - Private: Sustained-Speed Vehicle Detection

    private func updateSpeedWindow(timestamp: Date, speed: Double) {
        recentSpeedObservations.append((timestamp: timestamp, speed: speed))

        // Trim observations outside the rolling window.
        let cutoff = timestamp.addingTimeInterval(-RouteDistanceCalculator.sustainedVehicleDetectionWindowSeconds)
        recentSpeedObservations = recentSpeedObservations.filter { $0.timestamp >= cutoff }

        // Re-evaluate combined vehicle state (CMMotion OR sustained speed).
        let sustained = isSustainedVehicleSpeed()
        let combined = vehicleDetector.isInVehicle || sustained

        if isVehicleDetected != combined {
            isVehicleDetected = combined
            #if DEBUG
            if combined {
                let avg = averageRecentSpeed()
                print("[JoggingTrackingManager] Vehicle detected — CMMotion: \(vehicleDetector.isInVehicle), avgSpeed: \(String(format: "%.1f", avg)) m/s (\(String(format: "%.1f", avg * 3.6)) km/h)")
            } else {
                print("[JoggingTrackingManager] Vehicle detection cleared")
            }
            #endif
        }
    }

    /// Returns true when the rolling window contains enough data AND average speed
    /// exceeds the sustained vehicle threshold — indicating non-jogging movement.
    private func isSustainedVehicleSpeed() -> Bool {
        guard let oldest = recentSpeedObservations.first,
              let newest = recentSpeedObservations.last,
              newest.timestamp.timeIntervalSince(oldest.timestamp) >= RouteDistanceCalculator.sustainedVehicleMinWindowSeconds
        else { return false }

        return averageRecentSpeed() > RouteDistanceCalculator.sustainedVehicleSpeedThresholdMetersPerSecond
    }

    private func averageRecentSpeed() -> Double {
        guard !recentSpeedObservations.isEmpty else { return 0 }
        return recentSpeedObservations.map(\.speed).reduce(0, +) / Double(recentSpeedObservations.count)
    }

    /// Prefer GPS speed; when invalid (common on iOS), derive from last two route points.
    private func effectiveSpeedMetersPerSecond(latest: CLLocation?) -> Double {
        guard let latest else { return 0 }
        if latest.speed >= 0 { return latest.speed }
        guard routeLocations.count >= 2 else { return 0 }
        let a = routeLocations[routeLocations.count - 2]
        let b = routeLocations[routeLocations.count - 1]
        let dt = b.timestamp.timeIntervalSince(a.timestamp)
        guard dt > 0.2 else { return 0 }
        let d = b.distance(from: a)
        return d / dt
    }

    private func displaySpeedMetersPerSecond(latest: CLLocation?, now: Date) -> Double {
        guard isTracking, !isPaused, let latest else { return 0 }

        let age = now.timeIntervalSince(latest.timestamp)
        guard age <= speedValueStaleAfterSeconds else { return 0 }

        let rawSpeed = effectiveSpeedMetersPerSecond(latest: latest)
        guard rawSpeed.isFinite, rawSpeed >= stationarySpeedThresholdMetersPerSecond else { return 0 }

        return rawSpeed
    }

    private func currentPauseDuration(at now: Date) -> TimeInterval {
        let runningPause = pauseStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return accumulatedPauseDuration + runningPause
    }

    private func endCurrentSegment(at end: Date) {
        if isPaused {
            finalizeSegment(at: end, isPauseSegment: true)
            if let pauseStartedAt {
                accumulatedPauseDuration += max(0, end.timeIntervalSince(pauseStartedAt))
            }
            pauseStartedAt = nil
        } else {
            finalizeSegment(at: end, isPauseSegment: false)
        }
    }

    private func finalizeSegment(at end: Date, isPauseSegment: Bool) {
        guard let start = currentSegmentStartDate else { return }
        let duration = max(0, Int64(end.timeIntervalSince(start)))
        let distance = max(0, routeDistanceMeters - currentSegmentDistanceStart)
        let segment = LocalJoggingSegment(
            id: UUID().uuidString,
            startedAt: start,
            endedAt: end,
            distanceMeters: distance,
            durationSeconds: duration,
            isPause: isPauseSegment
        )
        segmentEvents.append(segment)
        currentSegmentDistanceStart = routeDistanceMeters
    }

    private func persistSegmentsIfPossible(sessionId: String?) async {
        guard let sessionId else { return }
        let mappedSegments: [Shared.JoggingSegment] = segmentEvents.map { segment in
            let startedAt = Kotlinx_datetimeInstant.companion.fromEpochMilliseconds(
                epochMilliseconds: Int64(segment.startedAt.timeIntervalSince1970 * 1000.0)
            )
            let endedAt = Kotlinx_datetimeInstant.companion.fromEpochMilliseconds(
                epochMilliseconds: Int64(segment.endedAt.timeIntervalSince1970 * 1000.0)
            )
            return Shared.JoggingSegment(
                id: segment.id,
                sessionId: sessionId,
                type: segment.isPause ? .pause : .run,
                startedAt: startedAt,
                endedAt: endedAt,
                distanceMeters: segment.distanceMeters,
                durationSeconds: segment.durationSeconds
            )
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let lock = NSLock()
                var hasResumed = false

                self.saveJoggingSegments.invoke(
                    sessionId: sessionId,
                    segments: mappedSegments
                ) { error in
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
                        continuation.resume(returning: ())
                    }
                }
            }
        } catch {
            #if DEBUG
            print("[JoggingTrackingManager] Failed to save jogging segments: \(error)")
            #endif
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
            lastFinishedSummary = summary
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

    private func endActivePlaybackEntry(at end: Date) {
        guard let activePlaybackEntry else { return }
        let normalizedEnd = max(end, activePlaybackEntry.startedAt)
        let duration = max(0, normalizedEnd.timeIntervalSince(activePlaybackEntry.startedAt))
        guard duration >= minimumPlaybackEntryDurationSeconds else {
            self.activePlaybackEntry = nil
            return
        }
        let endDistanceMeters = max(activePlaybackEntry.startDistanceMeters, activeDistanceMeters)
        let endActiveDurationSeconds = max(activePlaybackEntry.startActiveDurationSeconds, Int64(activeDuration))
        playbackEntries.append(
            LocalJoggingPlaybackEntry(
                id: activePlaybackEntry.id,
                source: activePlaybackEntry.source,
                trackTitle: activePlaybackEntry.trackTitle,
                artistName: activePlaybackEntry.artistName,
                spotifyTrackUri: activePlaybackEntry.spotifyTrackUri,
                startedAt: activePlaybackEntry.startedAt,
                endedAt: normalizedEnd,
                startDistanceMeters: activePlaybackEntry.startDistanceMeters,
                endDistanceMeters: endDistanceMeters,
                startActiveDurationSeconds: activePlaybackEntry.startActiveDurationSeconds,
                endActiveDurationSeconds: endActiveDurationSeconds
            )
        )
        self.activePlaybackEntry = nil
    }

    private func persistPlaybackEntriesIfPossible(sessionId: String?) async {
        guard let sessionId else { return }
        endActivePlaybackEntry(at: Date())
        let mappedEntries: [Shared.JoggingPlaybackEntry] = playbackEntries.map { entry in
            Shared.JoggingPlaybackEntry(
                id: entry.id,
                sessionId: sessionId,
                source: entry.source,
                trackTitle: entry.trackTitle,
                artistName: entry.artistName,
                spotifyTrackUri: entry.spotifyTrackUri,
                startedAt: Kotlinx_datetimeInstant.companion.fromEpochMilliseconds(
                    epochMilliseconds: Int64(entry.startedAt.timeIntervalSince1970 * 1000.0)
                ),
                endedAt: Kotlinx_datetimeInstant.companion.fromEpochMilliseconds(
                    epochMilliseconds: Int64(entry.endedAt.timeIntervalSince1970 * 1000.0)
                ),
                startDistanceMeters: entry.startDistanceMeters,
                endDistanceMeters: entry.endDistanceMeters,
                startActiveDurationSeconds: entry.startActiveDurationSeconds,
                endActiveDurationSeconds: entry.endActiveDurationSeconds
            )
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let lock = NSLock()
                var hasResumed = false

                self.saveJoggingPlaybackEntries.invoke(
                    sessionId: sessionId,
                    entries: mappedEntries
                ) { error in
                    lock.lock()
                    defer { lock.unlock() }
                    guard !hasResumed else { return }
                    hasResumed = true

                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        } catch {
            #if DEBUG
            print("[JoggingTrackingManager] Failed to persist playback entries: \(error)")
            #endif
        }
    }
}

private struct LocalJoggingSegment {
    let id: String
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let durationSeconds: Int64
    let isPause: Bool
}

private struct ActiveJoggingPlaybackEntry {
    let id: String
    let source: String
    let trackTitle: String
    let artistName: String?
    let spotifyTrackUri: String?
    let startedAt: Date
    let startDistanceMeters: Double
    let startActiveDurationSeconds: Int64
}

private struct LocalJoggingPlaybackEntry {
    let id: String
    let source: String
    let trackTitle: String
    let artistName: String?
    let spotifyTrackUri: String?
    let startedAt: Date
    let endedAt: Date
    let startDistanceMeters: Double
    let endDistanceMeters: Double
    let startActiveDurationSeconds: Int64
    let endActiveDurationSeconds: Int64
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
