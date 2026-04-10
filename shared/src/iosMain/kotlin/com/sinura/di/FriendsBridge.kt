package com.sinura.di

import com.sinura.domain.model.Friend
import com.sinura.domain.model.FriendLevelDetails
import com.sinura.domain.model.FriendMonthlyActivity
import com.sinura.domain.model.FriendActivityStats
import com.sinura.domain.model.FriendRequest
import com.sinura.domain.model.Friendship
import com.sinura.domain.model.UserSearchResult
import com.sinura.domain.repository.FriendshipRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.koin.core.component.KoinComponent
import org.koin.core.component.get

/**
 * iOS-facing bridge that exposes friendship operations to Swift.
 *
 * Network/IO work runs on [Dispatchers.Default] to keep the main thread free.
 * All callbacks are dispatched back on [Dispatchers.Main] so Swift ViewModels
 * can update @Published properties directly without DispatchQueue.main.async.
 *
 * Error messages passed to [onError] are user-facing strings only --
 * internal exception details are never forwarded to the UI layer.
 */
object FriendsBridge : KoinComponent {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

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
                withContext(Dispatchers.Main) { onResult(results) }
            } catch (e: Exception) {
                val msg = "Search failed: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
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
                withContext(Dispatchers.Main) { onResult(friendship) }
            } catch (e: Exception) {
                val msg = "Could not send friend request: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
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
                withContext(Dispatchers.Main) { onResult(requests) }
            } catch (e: Exception) {
                val msg = "Could not load friend requests: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
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
                withContext(Dispatchers.Main) { onResult(friendship) }
            } catch (e: Exception) {
                val msg = "Could not respond to the request: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
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
                withContext(Dispatchers.Main) { onResult(friends) }
            } catch (e: Exception) {
                val msg = "Could not load friends: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
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
                withContext(Dispatchers.Main) { onSuccess() }
            } catch (e: Exception) {
                val msg = "Could not remove friend: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }

    // =========================================================================
    // Friend stats
    // =========================================================================

    /**
     * Fetches activity statistics for a specific friend over a given period.
     *
     * @param friendId UUID of the friend whose stats are requested.
     * @param period   One of "day", "week", or "month".
     * @param onResult Called on the main thread with the [FriendActivityStats] result.
     * @param onError  Called on the main thread with a user-facing error message.
     */
    fun getFriendStats(
        friendId: String,
        period: String,
        onResult: (FriendActivityStats) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val stats = get<FriendshipRepository>().getFriendStats(friendId, period)
                withContext(Dispatchers.Main) { onResult(stats) }
            } catch (e: Exception) {
                val msg = "Could not load stats: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }

    fun getFriendMonthlyActivity(
        friendId: String,
        month: Int,
        year: Int,
        onResult: (FriendMonthlyActivity) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val summary = get<FriendshipRepository>().getFriendMonthlyActivity(friendId, month, year)
                withContext(Dispatchers.Main) { onResult(summary) }
            } catch (e: Exception) {
                val msg = "Could not load activity heatmap: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }

    fun getFriendLevelDetails(
        friendId: String,
        onResult: (FriendLevelDetails) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val details = get<FriendshipRepository>().getFriendLevelDetails(friendId)
                withContext(Dispatchers.Main) { onResult(details) }
            } catch (e: Exception) {
                val msg = "Could not load level details: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }
}
