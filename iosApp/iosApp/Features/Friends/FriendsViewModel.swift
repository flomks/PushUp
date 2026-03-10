import Foundation
import Shared

// MARK: - View-layer models

struct FriendItem: Identifiable {
    let id: String
    let username: String?
    let displayName: String?
    let avatarUrl: String?

    var displayLabel: String { displayName ?? username ?? "Unknown" }

    /// Returns "@username" only when both displayName and username are set,
    /// so the username is shown as a subtitle beneath the display name.
    var usernameLabel: String? {
        guard let u = username, displayName != nil else { return nil }
        return "@\(u)"
    }
}

struct FriendRequestItem: Identifiable {
    let id: String          // friendshipId used for accept/decline calls
    let requesterId: String
    let username: String?
    let displayName: String?
    let createdAt: String

    var displayLabel: String { displayName ?? username ?? "Unknown" }

    var usernameLabel: String? {
        guard let u = username, displayName != nil else { return nil }
        return "@\(u)"
    }
}

struct UserSearchItem: Identifiable {
    let id: String
    let username: String?
    let displayName: String?
    /// Raw status string from the KMP layer: "none" | "pending" | "friend"
    let friendshipStatus: String

    var displayLabel: String { displayName ?? username ?? "Unknown" }

    var usernameLabel: String? {
        guard let u = username, displayName != nil else { return nil }
        return "@\(u)"
    }
}

// MARK: - Leaderboard

/// A single ranked entry in the friends leaderboard.
struct LeaderboardEntry: Identifiable {
    let id: String
    let displayLabel: String
    let usernameLabel: String?
    let pushupCount: Int
    let totalSessions: Int
    let totalEarnedSeconds: Int64
    /// `true` when this entry represents the currently logged-in user.
    let isCurrentUser: Bool
}

// MARK: - Friend stats period

enum FriendStatsPeriod: String, CaseIterable, Identifiable {
    case day   = "day"
    case week  = "week"
    case month = "month"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day:   return "Today"
        case .week:  return "This Week"
        case .month: return "This Month"
        }
    }
}

// MARK: - Friend stats load state

enum FriendStatsLoadState: Equatable {
    case idle
    case loading
    case loaded(FriendStatsData)
    case error(String)
}

/// Snapshot of a friend's activity stats for a given period.
struct FriendStatsData: Equatable {
    let friendId: String
    let friendName: String
    let period: String
    let dateFrom: String
    let dateTo: String
    let pushupCount: Int
    let totalSessions: Int
    let totalEarnedSeconds: Int64
    /// Average form-quality score in [0, 1], nil when no sessions exist.
    let averageQuality: Double?
}

// MARK: - FriendsViewModel

/// Single ViewModel shared across all Friends sub-screens.
///
/// Owns:
/// - User search with debounce
/// - Incoming friend requests (accept / decline)
/// - Accepted friends list (remove)
/// - Friends leaderboard (parallel stats fetch, sorted by push-up count)
/// - Individual friend stats detail (period-switchable)
///
/// All `@Published` mutations happen on the main actor. `FriendsBridge`
/// guarantees its callbacks are dispatched on `Dispatchers.Main`, so no
/// additional `DispatchQueue.main.async` wrapping is needed.
@MainActor
final class FriendsViewModel: ObservableObject {

    // MARK: Search

    @Published var searchQuery: String = ""
    @Published var searchResults: [UserSearchItem] = []
    @Published var isSearching: Bool = false
    @Published var searchError: String? = nil
    @Published var sendingRequestIds: Set<String> = []

    // MARK: Incoming requests

    @Published var incomingRequests: [FriendRequestItem] = []
    @Published var isLoadingRequests: Bool = false
    @Published var requestsError: String? = nil
    @Published var respondingIds: Set<String> = []
    @Published var respondError: String? = nil

    // MARK: Friends list

    @Published var friends: [FriendItem] = []
    @Published var isLoadingFriends: Bool = false
    @Published var friendsError: String? = nil
    @Published var removingIds: Set<String> = []

    // MARK: Leaderboard

    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var isLoadingLeaderboard: Bool = false
    @Published var leaderboardError: String? = nil
    @Published var leaderboardPeriod: FriendStatsPeriod = .week

    // MARK: Friend stats detail

    @Published var friendStatsState: FriendStatsLoadState = .idle
    @Published var friendStatsPeriod: FriendStatsPeriod = .week

    // MARK: Private state

    private var searchTask: Task<Void, Never>? = nil
    private var leaderboardTask: Task<Void, Never>? = nil
    private var pushObservers: [NSObjectProtocol] = []

    /// The currently logged-in user, resolved once on first leaderboard load.
    private var currentUser: User? = nil
    /// All local workout sessions for the current user, kept in sync via DataBridge.
    private var localSessions: [WorkoutSession] = []
    /// KMP Flow observation job for local sessions (cancelled on deinit).
    private var sessionObservationJob: Kotlinx_coroutines_coreJob? = nil

    // MARK: Init / deinit

    init() {
        let requestObserver = NotificationCenter.default.addObserver(
            forName: .didReceiveFriendRequestPush,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.loadIncomingRequests() }

        let acceptedObserver = NotificationCenter.default.addObserver(
            forName: .didReceiveFriendAcceptedPush,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.loadFriends() }

        pushObservers = [requestObserver, acceptedObserver]

        // Resolve the current user and start observing local sessions so the
        // self-entry in the leaderboard always reflects up-to-date local data.
        Task { await self.startObservingOwnSessions() }
    }

    deinit {
        pushObservers.forEach { NotificationCenter.default.removeObserver($0) }
        sessionObservationJob?.cancel(cause: nil)
    }

    // MARK: - Search

    func onQueryChanged(_ query: String) {
        searchQuery = query
        searchError = nil

        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            searchTask?.cancel()
            return
        }

        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300 ms debounce
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        searchError = nil
        searchTask?.cancel()
    }

    private func performSearch(query: String) async {
        isSearching = true
        searchError = nil

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            FriendsBridge.shared.searchUsers(
                query: query,
                onResult: { [weak self] results in
                    guard let self else { continuation.resume(); return }
                    self.searchResults = results.map {
                        UserSearchItem(
                            id: $0.id,
                            username: $0.username,
                            displayName: $0.displayName,
                            friendshipStatus: $0.friendshipStatus.name.lowercased()
                        )
                    }
                    self.isSearching = false
                    continuation.resume()
                },
                onError: { [weak self] error in
                    guard let self else { continuation.resume(); return }
                    self.searchError = error
                    self.isSearching = false
                    continuation.resume()
                }
            )
        }
    }

    func sendFriendRequest(to userId: String) {
        guard !sendingRequestIds.contains(userId) else { return }
        sendingRequestIds.insert(userId)

        FriendsBridge.shared.sendFriendRequest(
            receiverId: userId,
            onResult: { [weak self] _ in
                guard let self else { return }
                self.sendingRequestIds.remove(userId)
                self.searchResults = self.searchResults.map {
                    guard $0.id == userId else { return $0 }
                    return UserSearchItem(
                        id: $0.id,
                        username: $0.username,
                        displayName: $0.displayName,
                        friendshipStatus: "pending"
                    )
                }
            },
            onError: { [weak self] _ in
                self?.sendingRequestIds.remove(userId)
            }
        )
    }

    // MARK: - Incoming Requests

    func loadIncomingRequests() {
        isLoadingRequests = true
        requestsError = nil

        FriendsBridge.shared.getIncomingFriendRequests(
            onResult: { [weak self] requests in
                guard let self else { return }
                self.incomingRequests = requests.map {
                    FriendRequestItem(
                        id: $0.friendshipId,
                        requesterId: $0.requesterId,
                        username: $0.username,
                        displayName: $0.displayName,
                        createdAt: $0.createdAt
                    )
                }
                self.isLoadingRequests = false
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.requestsError = error
                self.isLoadingRequests = false
            }
        )
    }

    func acceptRequest(_ friendshipId: String) { respondToRequest(friendshipId, accept: true) }
    func declineRequest(_ friendshipId: String) { respondToRequest(friendshipId, accept: false) }

    private func respondToRequest(_ friendshipId: String, accept: Bool) {
        guard !respondingIds.contains(friendshipId) else { return }
        respondingIds.insert(friendshipId)
        respondError = nil

        FriendsBridge.shared.respondToFriendRequest(
            friendshipId: friendshipId,
            accept: accept,
            onResult: { [weak self] _ in
                guard let self else { return }
                self.respondingIds.remove(friendshipId)
                self.incomingRequests.removeAll { $0.id == friendshipId }
                if accept { self.loadFriends() }
            },
            onError: { [weak self] _ in
                guard let self else { return }
                self.respondingIds.remove(friendshipId)
                self.respondError = accept
                    ? "Could not accept the request. Please try again."
                    : "Could not decline the request. Please try again."
            }
        )
    }

    func dismissRespondError() { respondError = nil }

    // MARK: - Friends List

    func loadFriends() {
        isLoadingFriends = true
        friendsError = nil

        FriendsBridge.shared.getFriends(
            onResult: { [weak self] friends in
                guard let self else { return }
                self.friends = friends.map {
                    FriendItem(
                        id: $0.id,
                        username: $0.username,
                        displayName: $0.displayName,
                        avatarUrl: $0.avatarUrl
                    )
                }
                self.isLoadingFriends = false
                // If the leaderboard tab was opened before friends finished loading,
                // populate it now that we have the friend list.
                self.loadLeaderboardIfReady()
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.friendsError = error
                self.isLoadingFriends = false
            }
        )
    }

    func removeFriend(_ friendId: String) {
        guard !removingIds.contains(friendId) else { return }
        removingIds.insert(friendId)

        FriendsBridge.shared.removeFriend(
            friendId: friendId,
            onSuccess: { [weak self] in
                guard let self else { return }
                self.removingIds.remove(friendId)
                self.friends.removeAll { $0.id == friendId }
                // Keep leaderboard in sync by removing the entry immediately.
                self.leaderboard.removeAll { $0.id == friendId }
            },
            onError: { [weak self] _ in
                self?.removingIds.remove(friendId)
            }
        )
    }

    // MARK: - Leaderboard

    /// Loads the leaderboard for the current period.
    ///
    /// If the friends list is empty, triggers a friends load first.
    /// Cancels any in-flight leaderboard fetch before starting a new one.
    func loadLeaderboard() {
        // If we have no friends yet, load them first; the leaderboard tab
        // calls this on appear so we need to handle the cold-start case.
        if friends.isEmpty && !isLoadingFriends {
            loadFriends()
        }

        guard !friends.isEmpty else {
            // Friends are loading; the leaderboard will be triggered once
            // friends arrive via loadLeaderboardIfReady().
            return
        }

        leaderboardTask?.cancel()
        leaderboardTask = Task { await fetchLeaderboard() }
    }

    /// Called after friends finish loading to auto-populate the leaderboard
    /// when the leaderboard tab is already visible.
    func loadLeaderboardIfReady() {
        guard !friends.isEmpty, leaderboard.isEmpty, !isLoadingLeaderboard else { return }
        leaderboardTask?.cancel()
        leaderboardTask = Task { await fetchLeaderboard() }
    }

    func selectLeaderboardPeriod(_ period: FriendStatsPeriod) {
        guard period != leaderboardPeriod else { return }
        leaderboardPeriod = period
        leaderboardTask?.cancel()
        leaderboardTask = Task { await fetchLeaderboard() }
    }

    /// Fetches stats for every friend in parallel using async/await + TaskGroup,
    /// prepends the current user's own entry, then sorts by push-up count descending.
    ///
    /// - Caps concurrent requests at the current friends count (no artificial limit
    ///   needed since the list is bounded by the API's 20-result search cap).
    /// - A failure for one friend produces a zero-count entry so they still appear.
    private func fetchLeaderboard() async {
        guard !Task.isCancelled else { return }

        isLoadingLeaderboard = true
        leaderboardError = nil

        let period = leaderboardPeriod.rawValue
        let snapshot = friends   // capture once; friends list won't mutate during fetch

        var entries: [LeaderboardEntry] = await withTaskGroup(
            of: LeaderboardEntry.self,
            returning: [LeaderboardEntry].self
        ) { group in
            for friend in snapshot {
                group.addTask { [weak self] in
                    guard let self else {
                        return LeaderboardEntry(
                            id: friend.id, displayLabel: friend.displayLabel,
                            usernameLabel: friend.usernameLabel,
                            pushupCount: 0, totalSessions: 0, totalEarnedSeconds: 0,
                            isCurrentUser: false
                        )
                    }
                    return await self.fetchStatsEntry(for: friend, period: period)
                }
            }
            var collected: [LeaderboardEntry] = []
            for await entry in group { collected.append(entry) }
            return collected
        }

        guard !Task.isCancelled else { return }

        // Add the current user's own entry so they appear in their own leaderboard.
        let userName = currentUser?.displayName ?? "You"
        if let own = selfEntry(for: period, displayName: userName) {
            entries.append(own)
        }

        entries.sort { $0.pushupCount > $1.pushupCount }
        leaderboard = entries
        isLoadingLeaderboard = false
    }

    // MARK: - Own session observation

    /// Resolves the current user once and starts a live Flow observation of
    /// their local workout sessions. Called from `init()`.
    private func startObservingOwnSessions() async {
        guard let user = await AuthService.shared.getCurrentUser() else { return }
        currentUser = user
        sessionObservationJob = DataBridge.shared.observeSessions(userId: user.id) { [weak self] sessions in
            self?.localSessions = sessions
        }
    }

    /// Builds a `LeaderboardEntry` for the current user by summing their local
    /// sessions that fall within the given [period] window.
    ///
    /// Uses the same period definitions as `FriendsBridge.getFriendStats`:
    ///   - "day"   → today (midnight … now)
    ///   - "week"  → last 7 days
    ///   - "month" → last 30 days
    private func selfEntry(for period: String, displayName: String) -> LeaderboardEntry? {
        guard let user = currentUser else { return nil }

        let now = Date()
        let calendar = Calendar.current

        let cutoff: Date
        switch period {
        case "day":
            cutoff = calendar.startOfDay(for: now)
        case "week":
            cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case "month":
            cutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        default:
            cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        }

        let cutoffMs = Int64(cutoff.timeIntervalSince1970 * 1000)

        let filtered = localSessions.filter { session in
            guard session.endedAt != nil else { return false }   // completed only
            return session.startedAt >= cutoffMs
        }

        let pushups = filtered.reduce(0) { $0 + Int($1.pushUpCount) }
        let sessions = filtered.count
        let earnedSeconds = filtered.reduce(Int64(0)) { $0 + $1.earnedTimeCreditSeconds }

        return LeaderboardEntry(
            id: user.id,
            displayLabel: displayName + " (You)",
            usernameLabel: nil,
            pushupCount: pushups,
            totalSessions: sessions,
            totalEarnedSeconds: earnedSeconds,
            isCurrentUser: true
        )
    }

    /// Wraps the callback-based `FriendsBridge.getFriendStats` in async/await.
    private func fetchStatsEntry(for friend: FriendItem, period: String) async -> LeaderboardEntry {
        await withCheckedContinuation { continuation in
            FriendsBridge.shared.getFriendStats(
                friendId: friend.id,
                period: period,
                onResult: { stats in
                    continuation.resume(returning: LeaderboardEntry(
                        id: friend.id,
                        displayLabel: friend.displayLabel,
                        usernameLabel: friend.usernameLabel,
                        pushupCount: Int(stats.pushupCount),
                        totalSessions: Int(stats.totalSessions),
                        totalEarnedSeconds: stats.totalEarnedSeconds,
                        isCurrentUser: false
                    ))
                },
                onError: { _ in
                    // Degrade gracefully: show the friend with zero stats rather
                    // than omitting them from the leaderboard entirely.
                    continuation.resume(returning: LeaderboardEntry(
                        id: friend.id,
                        displayLabel: friend.displayLabel,
                        usernameLabel: friend.usernameLabel,
                        pushupCount: 0,
                        totalSessions: 0,
                        totalEarnedSeconds: 0,
                        isCurrentUser: false
                    ))
                }
            )
        }
    }

    // MARK: - Friend Stats Detail

    /// Loads stats for a specific friend and period.
    ///
    /// Calling this while a load is already in flight for the same friend + period
    /// is a no-op to prevent redundant network requests.
    func loadFriendStats(friendId: String, friendName: String, period: FriendStatsPeriod) {
        // Avoid redundant reload if already showing the same data.
        if case .loaded(let data) = friendStatsState,
           data.friendId == friendId, data.period == period.rawValue {
            return
        }

        friendStatsState = .loading
        friendStatsPeriod = period

        FriendsBridge.shared.getFriendStats(
            friendId: friendId,
            period: period.rawValue,
            onResult: { [weak self] stats in
                guard let self else { return }
                self.friendStatsState = .loaded(FriendStatsData(
                    friendId: stats.friendId,
                    friendName: friendName,
                    period: stats.period,
                    dateFrom: stats.dateFrom,
                    dateTo: stats.dateTo,
                    pushupCount: Int(stats.pushupCount),
                    totalSessions: Int(stats.totalSessions),
                    totalEarnedSeconds: stats.totalEarnedSeconds,
                    // KotlinDouble? bridges to KotlinDouble? in Swift; .doubleValue extracts Double.
                    averageQuality: stats.averageQuality?.doubleValue
                ))
            },
            onError: { [weak self] error in
                self?.friendStatsState = .error(error)
            }
        )
    }

    /// Switches the stats period and reloads. Preserves the current friend context.
    func changeFriendStatsPeriod(to period: FriendStatsPeriod, friendId: String, friendName: String) {
        guard period != friendStatsPeriod else { return }
        friendStatsPeriod = period
        loadFriendStats(friendId: friendId, friendName: friendName, period: period)
    }

    /// Resets the stats detail state when navigating away from a friend's profile.
    /// Preserves the last-used period so it is remembered on the next open.
    func resetFriendStats() {
        friendStatsState = .idle
    }

    // MARK: - Computed

    var pendingRequestCount: Int { incomingRequests.count }
}
