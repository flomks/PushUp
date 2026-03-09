package com.pushup.di

import com.pushup.domain.model.Friend
import com.pushup.domain.model.FriendRequest
import com.pushup.domain.model.Friendship
import com.pushup.domain.model.UserSearchResult
import com.pushup.domain.repository.FriendshipRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.get

/**
 * iOS-facing bridge that exposes friendship operations to Swift.
 *
 * All callbacks are dispatched on [Dispatchers.Main] so Swift ViewModels
 * can update @Published properties directly.
 */
object FriendsBridge : KoinComponent {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // =========================================================================
    // User search
    // =========================================================================

    fun searchUsers(
        query: String,
        onResult: (List<UserSearchResult>) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val results = get<FriendshipRepository>().searchUsers(query)
                onResult(results)
            } catch (e: Exception) {
                onError(e.message ?: "Search failed")
            }
        }
    }

    // =========================================================================
    // Send friend request
    // =========================================================================

    fun sendFriendRequest(
        receiverId: String,
        onResult: (Friendship) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val friendship = get<FriendshipRepository>().sendFriendRequest(receiverId)
                onResult(friendship)
            } catch (e: Exception) {
                onError(e.message ?: "Failed to send request")
            }
        }
    }

    // =========================================================================
    // Incoming friend requests
    // =========================================================================

    fun getIncomingFriendRequests(
        onResult: (List<FriendRequest>) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val requests = get<FriendshipRepository>().getIncomingFriendRequests()
                onResult(requests)
            } catch (e: Exception) {
                onError(e.message ?: "Failed to load requests")
            }
        }
    }

    // =========================================================================
    // Respond to friend request
    // =========================================================================

    fun respondToFriendRequest(
        friendshipId: String,
        accept: Boolean,
        onResult: (Friendship) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val friendship = get<FriendshipRepository>().respondToFriendRequest(friendshipId, accept)
                onResult(friendship)
            } catch (e: Exception) {
                onError(e.message ?: "Failed to respond to request")
            }
        }
    }

    // =========================================================================
    // Friends list
    // =========================================================================

    fun getFriends(
        onResult: (List<Friend>) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val friends = get<FriendshipRepository>().getFriends()
                onResult(friends)
            } catch (e: Exception) {
                onError(e.message ?: "Failed to load friends")
            }
        }
    }

    // =========================================================================
    // Remove friend
    // =========================================================================

    fun removeFriend(
        friendId: String,
        onSuccess: () -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                get<FriendshipRepository>().removeFriend(friendId)
                onSuccess()
            } catch (e: Exception) {
                onError(e.message ?: "Failed to remove friend")
            }
        }
    }
}
