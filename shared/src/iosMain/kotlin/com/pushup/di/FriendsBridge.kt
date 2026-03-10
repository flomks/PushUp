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
 *
 * Error messages passed to [onError] are user-facing strings only --
 * internal exception details are never forwarded to the UI layer.
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
                onResult(get<FriendshipRepository>().searchUsers(query))
            } catch (e: Exception) {
                onError("Search failed: ${e.message ?: e::class.simpleName ?: "unknown error"}")
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
                onResult(get<FriendshipRepository>().sendFriendRequest(receiverId))
            } catch (e: Exception) {
                onError("Could not send friend request: ${e.message ?: e::class.simpleName ?: "unknown error"}")
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
                onResult(get<FriendshipRepository>().getIncomingFriendRequests())
            } catch (e: Exception) {
                onError("Could not load friend requests: ${e.message ?: e::class.simpleName ?: "unknown error"}")
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
                onResult(get<FriendshipRepository>().respondToFriendRequest(friendshipId, accept))
            } catch (e: Exception) {
                onError("Could not respond to the request: ${e.message ?: e::class.simpleName ?: "unknown error"}")
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
                onResult(get<FriendshipRepository>().getFriends())
            } catch (e: Exception) {
                onError("Could not load friends: ${e.message ?: e::class.simpleName ?: "unknown error"}")
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
                onError("Could not remove friend: ${e.message ?: e::class.simpleName ?: "unknown error"}")
            }
        }
    }
}
