package com.sinura.data.repository

import com.sinura.data.api.FriendshipApiClient
import com.sinura.domain.model.Friend
import com.sinura.domain.model.FriendActivityStats
import com.sinura.domain.model.FriendLevelDetails
import com.sinura.domain.model.FriendMonthlyActivity
import com.sinura.domain.model.Friendship
import com.sinura.domain.model.FriendRequest
import com.sinura.domain.model.UserSearchResult
import com.sinura.domain.repository.FriendshipRepository

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
