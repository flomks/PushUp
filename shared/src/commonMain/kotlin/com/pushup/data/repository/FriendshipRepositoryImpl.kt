package com.pushup.data.repository

import com.pushup.data.api.FriendshipApiClient
import com.pushup.domain.model.Friend
import com.pushup.domain.model.FriendActivityStats
import com.pushup.domain.model.FriendLevelDetails
import com.pushup.domain.model.FriendMonthlyActivity
import com.pushup.domain.model.Friendship
import com.pushup.domain.model.FriendRequest
import com.pushup.domain.model.UserSearchResult
import com.pushup.domain.repository.FriendshipRepository

/**
 * Production implementation of [FriendshipRepository].
 *
 * Delegates all operations to [FriendshipApiClient] which communicates with
 * the Ktor backend. All calls are already main-safe because Ktor's coroutine
 * dispatcher handles thread switching internally.
 *
 * @property apiClient The HTTP client for friendship and user-search endpoints.
 */
class FriendshipRepositoryImpl(
    private val apiClient: FriendshipApiClient,
) : FriendshipRepository {

    override suspend fun searchUsers(query: String): List<UserSearchResult> =
        apiClient.searchUsers(query)

    override suspend fun sendFriendRequest(receiverId: String): Friendship =
        apiClient.sendFriendRequest(receiverId)

    override suspend fun getIncomingFriendRequests(): List<FriendRequest> =
        apiClient.getIncomingFriendRequests()

    override suspend fun respondToFriendRequest(friendshipId: String, accept: Boolean): Friendship =
        apiClient.respondToFriendRequest(friendshipId, accept)

    override suspend fun getFriends(): List<Friend> =
        apiClient.getFriends()

    override suspend fun removeFriend(friendId: String) =
        apiClient.removeFriend(friendId)

    override suspend fun getFriendStats(friendId: String, period: String): FriendActivityStats =
        apiClient.getFriendStats(friendId, period)

    override suspend fun getFriendMonthlyActivity(friendId: String, month: Int, year: Int): FriendMonthlyActivity =
        apiClient.getFriendMonthlyActivity(friendId, month, year)

    override suspend fun getFriendLevelDetails(friendId: String): FriendLevelDetails =
        apiClient.getFriendLevelDetails(friendId)
}
