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

struct ActiveRunOption: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let participantCount: Int
}

struct UpcomingRunOption: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let participantCount: Int
    let status: String?
}

enum RunAudioMode: String, CaseIterable, Identifiable {
    case recovery = "Recovery"
    case base = "Base"
    case tempo = "Tempo"
    case longRun = "Long Run"
    case race = "Race"

    var id: String { rawValue }
}

struct RunTrack: Equatable {
    let title: String
    let artist: String
    let vibe: String
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
    @Published private(set) var activeFriendRuns: [ActiveRunOption] = []
    @Published private(set) var upcomingRuns: [UpcomingRunOption] = []
    @Published private(set) var isLoadingRunSocialData: Bool = false
    @Published private(set) var selectedLiveRunSessionId: String?
    @Published private(set) var selectedUpcomingEventId: String?
    @Published var plannedRunTitle: String = "Crew Run"
    @Published var plannedRunDate: Date = JoggingViewModel.defaultPlannedRunDate()
    @Published private(set) var isCreatingPlannedRun: Bool = false
    @Published private(set) var plannedRunStatusMessage: String?
    @Published private(set) var isUpdatingUpcomingRun: Bool = false
    @Published private(set) var isInvitingToLiveRun: Bool = false
    @Published private(set) var isLeavingLiveRun: Bool = false
    @Published private(set) var isRejoiningLiveRun: Bool = false
    @Published private(set) var activeRunLeaderName: String?
    @Published private(set) var activeRunStateLabel: String?
    @Published private(set) var liveRunBannerMessage: String?
    @Published private(set) var lastDetachedLiveRunSessionId: String?
    @Published var selectedAudioMode: RunAudioMode = .base
    @Published private(set) var spotifyConnected: Bool = false
    @Published private(set) var jamActive: Bool = false
    @Published private(set) var jamListenerCount: Int = 1
    @Published private(set) var jamHostDisplayName: String = "You"
    @Published private(set) var isCurrentUserInJam: Bool = false
    @Published private(set) var currentTrack: RunTrack = RunTrack(
        title: "Night Drive Tempo",
        artist: "PushUp Run Club",
        vibe: "160 BPM • Focus"
    )

    // MARK: - Private

    let trackingManager: JoggingTrackingManager
    private var cancellables = Set<AnyCancellable>()
    private var joggingObservationJob: Kotlinx_coroutines_coreJob?
    private var liveRunObservationJob: Kotlinx_coroutines_coreJob?
    private var currentUserId: String?
    private var currentUserDisplayName: String = "You"
    private var currentUsername: String?
    private var presenceHeartbeat: AnyCancellable?
    private var socialRefreshTimer: AnyCancellable?
    private var activeSessionRefreshTimer: AnyCancellable?
    private var liveRunBannerResetTask: Task<Void, Never>?
    private var lastObservedLeaderUserId: String?

    // MARK: - Init

    /// Creates a view model with the given tracking manager.
    /// Must be called from the main actor since JoggingTrackingManager is @MainActor-isolated.
    init(trackingManager: JoggingTrackingManager) {
        self.trackingManager = trackingManager
        applyTrackPresetForMode()
        observeTrackingManager()
        startSocialRefreshLoop()
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
        Task { await startWorkoutFlow() }
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
        if let sessionId = selectedLiveRunSessionId, let userId = currentUserId {
            DataBridge.shared.finishLiveRunSession(sessionId: sessionId, userId: userId) { _ in }
        }
        trackingManager.stopTracking()
        stopPresenceHeartbeat()
        stopActiveSessionRefreshLoop()
        activeRunStateLabel = nil
        activeRunLeaderName = nil
        clearLiveRunBanner()
        selectedLiveRunSessionId = nil
        lastDetachedLiveRunSessionId = nil
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
            currentUserId = currentUser.id
            let safeDisplayName = currentUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            currentUserDisplayName = safeDisplayName.isEmpty ? "You" : safeDisplayName
            currentUsername = currentUser.username
            let me = RunParticipant(
                id: currentUser.id,
                displayName: currentUserDisplayName,
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
                    continuation.resume()
                },
                onError: { [weak self] _ in
                    self?.inviteableFriends = []
                    continuation.resume()
                }
            )
        }

        await refreshRunOptions()
        isLoadingRunSocialData = false
    }

    func inviteFriendToRun(_ friendId: String) {
        Task { await inviteFriendToRunFlow(friendId) }
    }

    private func inviteFriendToRunFlow(_ friendId: String) async {
        if let sessionId = selectedLiveRunSessionId {
            guard !isInvitingToLiveRun else { return }
            isInvitingToLiveRun = true
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DataBridge.shared.inviteUserToLiveRunSession(sessionId: sessionId, userId: friendId) { [weak self] success in
                    guard let self else {
                        continuation.resume()
                        return
                    }
                    self.isInvitingToLiveRun = false
                    self.plannedRunStatusMessage = success.boolValue ? "Live run invite sent." : "Failed to invite runner."
                    Task {
                        await self.loadRunSocialData()
                    }
                    continuation.resume()
                }
            }
            return
        }

        guard let idx = inviteableFriends.firstIndex(where: { $0.id == friendId }) else { return }
        var invited = inviteableFriends.remove(at: idx)
        invited.status = .invited
        if !runParticipants.contains(where: { $0.id == invited.id }) {
            runParticipants.append(invited)
        }
        plannedRunStatusMessage = nil
    }

    func createPlannedRun() {
        Task { await createPlannedRunFlow() }
    }

    func acceptUpcomingRun(_ eventId: String) {
        Task { await respondToUpcomingRun(eventId: eventId, accept: true) }
    }

    func declineUpcomingRun(_ eventId: String) {
        Task { await respondToUpcomingRun(eventId: eventId, accept: false) }
    }

    func checkInUpcomingRun(_ eventId: String) {
        Task { await checkInUpcomingRunFlow(eventId: eventId) }
    }

    func leaveCurrentLiveRun() {
        Task { await leaveCurrentLiveRunFlow() }
    }

    func rejoinLastLiveRun() {
        Task { await rejoinLastLiveRunFlow() }
    }

    func connectSpotify() {
        spotifyConnected = true
        plannedRunStatusMessage = "Spotify ready for your next run."
    }

    func cycleAudioMode() {
        let allModes = RunAudioMode.allCases
        guard let currentIndex = allModes.firstIndex(of: selectedAudioMode) else { return }
        let nextIndex = allModes.index(after: currentIndex)
        selectedAudioMode = nextIndex < allModes.endIndex ? allModes[nextIndex] : allModes[allModes.startIndex]
        applyTrackPresetForMode()
    }

    func startJam() {
        spotifyConnected = true
        jamActive = true
        isCurrentUserInJam = true
        jamListenerCount = max(runParticipants.filter { $0.status == .running }.count, 1)
        jamHostDisplayName = currentUserDisplayName
        showLiveRunBanner("Run Jam started on Spotify.")
    }

    func joinJam() {
        spotifyConnected = true
        jamActive = true
        isCurrentUserInJam = true
        jamListenerCount = max(jamListenerCount, max(runParticipants.filter { $0.status == .running }.count, 1))
        showLiveRunBanner("You joined the Run Jam.")
    }

    func leaveJam() {
        isCurrentUserInJam = false
        jamListenerCount = max(jamListenerCount - 1, 0)
        if jamListenerCount == 0 {
            jamActive = false
        }
        showLiveRunBanner("You left the Run Jam.")
    }

    func nextTrack() {
        applyTrackPresetForMode(advance: true)
    }

    func selectActiveRun(_ sessionId: String) {
        selectedLiveRunSessionId = sessionId
        selectedUpcomingEventId = nil
    }

    func selectUpcomingRun(_ eventId: String) {
        selectedUpcomingEventId = eventId
        selectedLiveRunSessionId = nil
    }

    var startActionTitle: String {
        if selectedLiveRunSessionId != nil {
            return "Join Run"
        }
        if selectedUpcomingEventId != nil {
            return "Start Planned Run"
        }
        if runParticipants.contains(where: { $0.status == .invited }) {
            return "Start Crew Run"
        }
        return hasLocationPermission ? "Start Run" : "Enable Location"
    }

    var socialSelectionSummary: String {
        if let activeRun = activeFriendRuns.first(where: { $0.id == selectedLiveRunSessionId }) {
            return activeRun.subtitle
        }
        if let upcomingRun = upcomingRuns.first(where: { $0.id == selectedUpcomingEventId }) {
            return upcomingRun.subtitle
        }
        let invitedCount = runParticipants.filter { $0.status == .invited }.count
        if invitedCount > 0 {
            return "\(invitedCount) invited - friends-visible live session"
        }
        return "Solo run"
    }

    var canCreatePlannedRun: Bool {
        currentUserId != nil &&
        !plannedRunTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        runParticipants.contains(where: { $0.status == .invited })
    }

    var musicCardSubtitle: String {
        if !spotifyConnected {
            return "Connect Spotify"
        }
        if jamActive {
            return isCurrentUserInJam ? "Jam live with \(jamListenerCount) runners" : "Jam active - join now"
        }
        return currentTrack.title
    }

    var jamStatusLabel: String {
        if jamActive {
            return isCurrentUserInJam
                ? "Jam live • \(jamListenerCount) listening"
                : "Jam active • hosted by \(jamHostDisplayName)"
        }
        return spotifyConnected ? "Solo audio" : "Spotify disconnected"
    }

    var musicPrimaryActionTitle: String {
        if !spotifyConnected { return "Connect Spotify" }
        if jamActive {
            return isCurrentUserInJam ? "Leave Jam" : "Join Jam"
        }
        return selectedLiveRunSessionId != nil ? "Start Jam" : "Play Solo"
    }

    func upcomingRunPrimaryActionTitle(for run: UpcomingRunOption) -> String {
        switch run.status?.uppercased() {
        case "CHECKED_IN":
            return selectedUpcomingEventId == run.id ? "Selected" : "Ready"
        case "ACCEPTED":
            return selectedUpcomingEventId == run.id ? "Selected" : "Check In"
        case "INVITED":
            return "Accept"
        case "DECLINED":
            return "Rejoin"
        default:
            return selectedUpcomingEventId == run.id ? "Selected" : "Queue"
        }
    }

    func handleUpcomingRunPrimaryAction(_ run: UpcomingRunOption) {
        switch run.status?.uppercased() {
        case "CHECKED_IN":
            selectUpcomingRun(run.id)
        case "ACCEPTED":
            checkInUpcomingRun(run.id)
        case "INVITED", "DECLINED":
            acceptUpcomingRun(run.id)
        default:
            selectUpcomingRun(run.id)
        }
    }

    private func startWorkoutFlow() async {
        guard hasLocationPermission else {
            requestLocationPermission()
            return
        }

        let resolvedUserId = currentUserId ?? (await AuthService.shared.getCurrentUser())?.id
        guard let userId = resolvedUserId else {
            phase = .active
            UIApplication.shared.isIdleTimerDisabled = true
            trackingManager.startTracking()
            return
        }

        let linkedLiveSessionId: String?
        if let existingSessionId = selectedLiveRunSessionId {
            linkedLiveSessionId = await joinSelectedLiveRun(sessionId: existingSessionId, userId: userId)
        } else if let upcomingEventId = selectedUpcomingEventId {
            linkedLiveSessionId = await startLiveRun(userId: userId, linkedEventId: upcomingEventId)
        } else if runParticipants.contains(where: { $0.status == .invited }) {
            linkedLiveSessionId = await startLiveRun(userId: userId, linkedEventId: nil)
        } else {
            linkedLiveSessionId = nil
        }

        phase = .active
        UIApplication.shared.isIdleTimerDisabled = true
        trackingManager.startTracking(liveRunSessionId: linkedLiveSessionId)

        if let linkedLiveSessionId {
            beginObservingLiveRun(sessionId: linkedLiveSessionId)
            startPresenceHeartbeat()
            startActiveSessionRefreshLoop(sessionId: linkedLiveSessionId)
        }
    }

    private func refreshRunOptions() async {
        guard let userId = currentUserId else {
            activeFriendRuns = []
            upcomingRuns = []
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.fetchFriendsActiveRuns(userId: userId) { [weak self] sessions in
                self?.activeFriendRuns = sessions.map {
                    ActiveRunOption(
                        id: $0.id,
                        title: "Live Run",
                        subtitle: "\($0.participantCount) runners - \($0.state.capitalized)",
                        participantCount: Int($0.participantCount)
                    )
                }
                continuation.resume()
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.fetchUpcomingRunEvents(userId: userId) { [weak self] events in
                self?.upcomingRuns = events.map {
                    UpcomingRunOption(
                        id: $0.id,
                        title: $0.title,
                        subtitle: Self.formatUpcomingSubtitle(
                            plannedStartAt: $0.plannedStartAt,
                            participantCount: Int($0.participantCount)
                        ),
                        participantCount: Int($0.participantCount),
                        status: $0.currentUserStatus
                    )
                }
                continuation.resume()
            }
        }
    }

    private func createPlannedRunFlow() async {
        guard !isCreatingPlannedRun else { return }
        guard let userId = currentUserId else { return }
        let inviteIds = runParticipants
            .filter { $0.status == .invited }
            .map(\.id)
        guard !inviteIds.isEmpty else {
            plannedRunStatusMessage = "Invite at least one friend first."
            return
        }

        let trimmedTitle = plannedRunTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            plannedRunStatusMessage = "Add a title for the planned run."
            return
        }

        isCreatingPlannedRun = true
        plannedRunStatusMessage = nil
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.createRunEvent(
                organizerUserId: userId,
                title: trimmedTitle,
                mode: "BASE",
                visibility: "FRIENDS",
                plannedStartAt: isoFormatter.string(from: plannedRunDate),
                invitedUserIds: inviteIds,
                description: nil,
                plannedEndAt: nil,
                locationName: nil
            ) { [weak self] event in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.isCreatingPlannedRun = false
                if let event {
                    self.selectedUpcomingEventId = event.id
                    self.selectedLiveRunSessionId = nil
                    self.plannedRunStatusMessage = "Planned run created."
                    Task { await self.refreshRunOptions() }
                } else {
                    self.plannedRunStatusMessage = "Failed to create planned run."
                }
                continuation.resume()
            }
        }
    }

    private func respondToUpcomingRun(eventId: String, accept: Bool) async {
        guard let userId = currentUserId, !isUpdatingUpcomingRun else { return }
        isUpdatingUpcomingRun = true
        plannedRunStatusMessage = nil

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.respondToRunEvent(
                eventId: eventId,
                userId: userId,
                status: accept ? "ACCEPTED" : "DECLINED"
            ) { [weak self] success in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.isUpdatingUpcomingRun = false
                self.plannedRunStatusMessage = success.boolValue
                    ? (accept ? "Joined planned run." : "Declined planned run.")
                    : "Failed to update planned run."
                Task { await self.refreshRunOptions() }
                continuation.resume()
            }
        }
    }

    private func checkInUpcomingRunFlow(eventId: String) async {
        guard let userId = currentUserId, !isUpdatingUpcomingRun else { return }
        isUpdatingUpcomingRun = true
        plannedRunStatusMessage = nil

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.checkInRunEvent(eventId: eventId, userId: userId) { [weak self] success in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.isUpdatingUpcomingRun = false
                self.plannedRunStatusMessage = success.boolValue ? "Checked in for planned run." : "Failed to check in."
                Task { await self.refreshRunOptions() }
                continuation.resume()
            }
        }
    }

    private func startLiveRun(userId: String, linkedEventId: String?) async -> String? {
        await withCheckedContinuation { continuation in
            DataBridge.shared.startLiveRunSession(
                leaderUserId: userId,
                mode: "BASE",
                visibility: "FRIENDS",
                linkedEventId: linkedEventId
            ) { [weak self] result in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                let sessionId = result?.id
                if let sessionId {
                    self.selectedLiveRunSessionId = sessionId
                    self.selectedUpcomingEventId = nil
                }
                continuation.resume(returning: sessionId)
            }
        }
    }

    private func joinSelectedLiveRun(sessionId: String, userId: String) async -> String? {
        await withCheckedContinuation { continuation in
            DataBridge.shared.joinLiveRunSession(sessionId: sessionId, userId: userId) { success in
                continuation.resume(returning: success.boolValue ? sessionId : nil)
            }
        }
    }

    private func beginObservingLiveRun(sessionId: String) {
        liveRunObservationJob?.cancel(cause: nil)
        lastObservedLeaderUserId = nil
        liveRunObservationJob = DataBridge.shared.observeLiveRunSession(sessionId: sessionId) { [weak self] snapshot in
            self?.applyLiveRunSnapshot(snapshot)
        }
    }

    private func participantViewModel(userId: String, status: String) -> RunParticipant {
        let known = defaultRunParticipants().first(where: { $0.id == userId })
        let normalizedStatus = status.uppercased()
        return RunParticipant(
            id: userId,
            displayName: known?.displayName ?? displayName(for: userId),
            username: known?.username ?? (userId == currentUserId ? currentUsername : nil),
            status: normalizedStatus == "INVITED" ? .invited : .running
        )
    }

    private func defaultRunParticipants() -> [RunParticipant] {
        var base: [RunParticipant] = []
        if let userId = currentUserId {
            base.append(
                RunParticipant(
                    id: userId,
                    displayName: currentUserDisplayName,
                    username: currentUsername,
                    status: .running
                )
            )
        }
        base.append(contentsOf: runParticipants.filter { participant in
            base.contains(where: { $0.id == participant.id }) == false
        })
        return base
    }

    private func startPresenceHeartbeat() {
        stopPresenceHeartbeat()
        presenceHeartbeat = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pushPresenceHeartbeat()
            }
    }

    private func stopPresenceHeartbeat() {
        presenceHeartbeat?.cancel()
        presenceHeartbeat = nil
    }

    private func startActiveSessionRefreshLoop(sessionId: String) {
        activeSessionRefreshTimer?.cancel()
        activeSessionRefreshTimer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshActiveSessionSnapshot(sessionId: sessionId)
            }
    }

    private func stopActiveSessionRefreshLoop() {
        activeSessionRefreshTimer?.cancel()
        activeSessionRefreshTimer = nil
    }

    private func startSocialRefreshLoop() {
        socialRefreshTimer?.cancel()
        socialRefreshTimer = Timer.publish(every: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshRunOptions() }
            }
    }

    private func pushPresenceHeartbeat() {
        guard phase == .active,
              let sessionId = selectedLiveRunSessionId,
              let userId = currentUserId else { return }
        let location = routeLocations.last
        let paceSecondsPerKm: Int32? = currentPaceSecondsPerKm.map { Int32($0) }
        DataBridge.shared.updateLiveRunPresence(
            sessionId: sessionId,
            userId: userId,
            state: isPaused ? "PAUSED" : "ACTIVE",
            distanceMeters: distanceMeters,
            durationSeconds: Int64(activeDuration),
            paceSecondsPerKm: paceSecondsPerKm,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude
        ) { _ in }
    }

    private func handleObservedLeaderChange(newLeaderUserId: String) {
        defer { lastObservedLeaderUserId = newLeaderUserId }
        guard let previousLeaderUserId = lastObservedLeaderUserId,
              previousLeaderUserId != newLeaderUserId else { return }

        let previousName = displayName(for: previousLeaderUserId)
        let newName = displayName(for: newLeaderUserId)
        showLiveRunBanner("\(previousName) finished. \(newName) leads now.")
    }

    private func displayName(for userId: String) -> String {
        if userId == currentUserId {
            return currentUserDisplayName
        }
        if let knownFriend = inviteableFriends.first(where: { $0.id == userId }) {
            return knownFriend.displayName
        }
        if let knownRunner = runParticipants.first(where: { $0.id == userId }) {
            return knownRunner.displayName
        }
        return "Runner"
    }

    private func labelForLiveState(_ raw: String) -> String? {
        switch raw.uppercased() {
        case "LIVE":
            return activeRunLeaderName.map { "Leader: \($0)" } ?? "Crew live"
        case "COOLDOWN":
            return "Cooldown"
        case "FINISHED":
            return "Finished"
        default:
            return nil
        }
    }

    private func applyTrackPresetForMode(advance: Bool = false) {
        let options: [RunAudioMode: [RunTrack]] = [
            .recovery: [
                RunTrack(title: "Soft Horizon", artist: "PushUp Run Club", vibe: "118 BPM • Recovery"),
                RunTrack(title: "Cool Down Signal", artist: "PushUp Run Club", vibe: "112 BPM • Easy")
            ],
            .base: [
                RunTrack(title: "Night Drive Tempo", artist: "PushUp Run Club", vibe: "160 BPM • Focus"),
                RunTrack(title: "City Grid Stride", artist: "PushUp Run Club", vibe: "158 BPM • Base")
            ],
            .tempo: [
                RunTrack(title: "Redline District", artist: "PushUp Run Club", vibe: "174 BPM • Tempo"),
                RunTrack(title: "Split Hunter", artist: "PushUp Run Club", vibe: "176 BPM • Fast")
            ],
            .longRun: [
                RunTrack(title: "Endless Blocks", artist: "PushUp Run Club", vibe: "148 BPM • Durable"),
                RunTrack(title: "Sunday Engine", artist: "PushUp Run Club", vibe: "150 BPM • Cruise")
            ],
            .race: [
                RunTrack(title: "Start Gun", artist: "PushUp Run Club", vibe: "182 BPM • Race"),
                RunTrack(title: "Final Kick", artist: "PushUp Run Club", vibe: "186 BPM • Push")
            ]
        ]

        let tracks = options[selectedAudioMode] ?? []
        guard !tracks.isEmpty else { return }
        if advance, let currentIndex = tracks.firstIndex(of: currentTrack) {
            let nextIndex = tracks.index(after: currentIndex)
            currentTrack = nextIndex < tracks.endIndex ? tracks[nextIndex] : tracks[tracks.startIndex]
        } else {
            currentTrack = tracks[tracks.startIndex]
        }
    }

    private func showLiveRunBanner(_ message: String) {
        liveRunBannerResetTask?.cancel()
        liveRunBannerMessage = message
        liveRunBannerResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.liveRunBannerMessage = nil
            }
        }
    }

    private func clearLiveRunBanner() {
        liveRunBannerResetTask?.cancel()
        liveRunBannerResetTask = nil
        liveRunBannerMessage = nil
    }

    private func refreshActiveSessionSnapshot(sessionId: String) {
        DataBridge.shared.fetchLiveRunSessionSnapshot(sessionId: sessionId) { [weak self] snapshot in
            guard let self, let snapshot else { return }
            self.applyLiveRunSnapshot(snapshot)
        }
    }

    private func applyLiveRunSnapshot(_ snapshot: LiveRunSessionSnapshotResult) {
        let mapped = snapshot.participants.map { participant in
            participantViewModel(
                userId: participant.userId,
                status: participant.status
            )
        }
        runParticipants = mapped.isEmpty ? defaultRunParticipants() : mapped
        if let session = snapshot.session {
            handleObservedLeaderChange(newLeaderUserId: session.leaderUserId)
            activeRunLeaderName = displayName(for: session.leaderUserId)
            activeRunStateLabel = labelForLiveState(session.state)
            if session.state.uppercased() == "COOLDOWN" {
                showLiveRunBanner("Run is in cooldown. Jump back in before it closes.")
            } else if session.state.uppercased() == "FINISHED" {
                showLiveRunBanner("Group run finished.")
                stopActiveSessionRefreshLoop()
            }
        } else {
            activeRunLeaderName = nil
            activeRunStateLabel = nil
        }
    }

    private func leaveCurrentLiveRunFlow() async {
        guard let sessionId = selectedLiveRunSessionId,
              let userId = currentUserId,
              !isLeavingLiveRun else { return }
        isLeavingLiveRun = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.leaveLiveRunSession(sessionId: sessionId, userId: userId) { [weak self] success in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.isLeavingLiveRun = false
                if success.boolValue {
                    self.stopPresenceHeartbeat()
                    self.stopActiveSessionRefreshLoop()
                    self.liveRunObservationJob?.cancel(cause: nil)
                    self.selectedLiveRunSessionId = nil
                    self.lastDetachedLiveRunSessionId = sessionId
                    self.activeRunLeaderName = nil
                    self.activeRunStateLabel = "Solo run"
                    self.runParticipants = self.defaultRunParticipants()
                    self.showLiveRunBanner("You left the crew run and continued solo.")
                } else {
                    self.showLiveRunBanner("Failed to leave crew run.")
                }
                continuation.resume()
            }
        }
    }

    private func rejoinLastLiveRunFlow() async {
        guard let sessionId = lastDetachedLiveRunSessionId,
              let userId = currentUserId,
              !isRejoiningLiveRun,
              phase == .active else { return }
        isRejoiningLiveRun = true

        let joinedSessionId = await joinSelectedLiveRun(sessionId: sessionId, userId: userId)
        isRejoiningLiveRun = false

        guard let joinedSessionId else {
            showLiveRunBanner("Rejoin failed. The crew run may have already ended.")
            return
        }

        selectedLiveRunSessionId = joinedSessionId
        lastDetachedLiveRunSessionId = nil
        beginObservingLiveRun(sessionId: joinedSessionId)
        startPresenceHeartbeat()
        startActiveSessionRefreshLoop(sessionId: joinedSessionId)
        pushPresenceHeartbeat()
        showLiveRunBanner("You rejoined the crew run.")
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
        let totalSeconds = max(0, Int(activeDuration))
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

    private static func formatUpcomingSubtitle(plannedStartAt: String, participantCount: Int) -> String {
        let fallback = "\(participantCount) runners planned"
        guard let date = ISO8601DateFormatter().date(from: plannedStartAt) else { return fallback }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d • HH:mm"
        return "\(formatter.string(from: date)) - \(participantCount) runners"
    }

    private static func defaultPlannedRunDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.date(
            bySettingHour: 7,
            minute: 0,
            second: 0,
            of: tomorrow
        ) ?? tomorrow
    }

    deinit {
        joggingObservationJob?.cancel(cause: nil)
        liveRunObservationJob?.cancel(cause: nil)
        presenceHeartbeat?.cancel()
        socialRefreshTimer?.cancel()
        activeSessionRefreshTimer?.cancel()
        liveRunBannerResetTask?.cancel()
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
