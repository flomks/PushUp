import Foundation
import Shared

// MARK: - View-layer models

struct FriendItem: Identifiable {
    let id: String
    let username: String?
    let displayName: String?
    let avatarUrl: String?

    var displayLabel: String {
        displayName ?? username ?? "Unknown"
    }

    var usernameLabel: String? {
        guard let u = username, displayName != nil else { return nil }
        return "@\(u)"
    }
}

struct FriendRequestItem: Identifiable {
    let id: String          // friendshipId
    let requesterId: String
    let username: String?
    let displayName: String?
    let createdAt: String

    var displayLabel: String {
        displayName ?? username ?? "Unknown"
    }

    var usernameLabel: String? {
        guard let u = username, displayName != nil else { return nil }
        return "@\(u)"
    }
}

struct UserSearchItem: Identifiable {
    let id: String
    let username: String?
    let displayName: String?
    let friendshipStatus: String   // "none" | "pending" | "friend"

    var displayLabel: String {
        displayName ?? username ?? "Unknown"
    }

    var usernameLabel: String? {
        guard let u = username, displayName != nil else { return nil }
        return "@\(u)"
    }
}

// MARK: - FriendsViewModel

@MainActor
final class FriendsViewModel: ObservableObject {

    // Search
    @Published var searchQuery: String = ""
    @Published var searchResults: [UserSearchItem] = []
    @Published var isSearching: Bool = false
    @Published var searchError: String? = nil
    @Published var sendingRequestIds: Set<String> = []

    // Incoming requests
    @Published var incomingRequests: [FriendRequestItem] = []
    @Published var isLoadingRequests: Bool = false
    @Published var requestsError: String? = nil
    @Published var respondingIds: Set<String> = []
    @Published var respondError: String? = nil

    // Friends list
    @Published var friends: [FriendItem] = []
    @Published var isLoadingFriends: Bool = false
    @Published var friendsError: String? = nil
    @Published var removingIds: Set<String> = []

    private var searchTask: Task<Void, Never>? = nil

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
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
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

        // Bridge the KMP callback into async/await.
        // FriendsBridge dispatches callbacks on Dispatchers.Main so the
        // continuation is always resumed on the main thread — safe for
        // @MainActor ViewModels.
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
                // Optimistically update status in search results
                self.searchResults = self.searchResults.map {
                    $0.id == userId
                        ? UserSearchItem(id: $0.id, username: $0.username,
                                         displayName: $0.displayName, friendshipStatus: "pending")
                        : $0
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

    func acceptRequest(_ friendshipId: String) {
        respondToRequest(friendshipId, accept: true)
    }

    func declineRequest(_ friendshipId: String) {
        respondToRequest(friendshipId, accept: false)
    }

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
            onError: { [weak self] error in
                guard let self else { return }
                self.respondingIds.remove(friendshipId)
                self.respondError = accept
                    ? "Could not accept the request. Please try again."
                    : "Could not decline the request. Please try again."
            }
        )
    }

    func dismissRespondError() {
        respondError = nil
    }

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
            },
            onError: { [weak self] _ in
                self?.removingIds.remove(friendId)
            }
        )
    }

    // MARK: - Computed

    var pendingRequestCount: Int { incomingRequests.count }
}
