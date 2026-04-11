package com.sinura.domain.repository

import com.sinura.domain.model.Friend
import com.sinura.domain.model.FriendLevelDetails
import com.sinura.domain.model.FriendMonthlyActivity
import com.sinura.domain.model.FriendActivityStats
import com.sinura.domain.model.Friendship
import com.sinura.domain.model.FriendRequest
import com.sinura.domain.model.UserSearchResult

/**
 * Repository for user search and friendship management.
 *
 * All implementations must be **main-safe** -- dispatcher switching is handled internally.
 */
interface FriendshipRepository {

    /**
     * Searches for users whose username or display name contains [query].
     *
     * - The authenticated caller is excluded from results.
     * - Each result is annotated with the friendship status relative to the caller.
     * - Returns up to 20 results.
     *
     * @param query Search term (minimum 2 characters).
     * @return List of matching [UserSearchResult]s.
     * @throws com.sinura.data.api.ApiException on network or server errors.
     */
    suspend fun searchUsers(query: String): List<UserSearchResult>

    /**
     * Sends a friend request from the authenticated user to [receiverId].
     *
     * @param receiverId UUID of the user to send the request to.
     * @return The created [Friendship] record.
     * @throws com.sinura.data.api.ApiException on network or server errors.
     */
    suspend fun sendFriendRequest(receiverId: String): Friendship

    /**
     * Returns all incoming pending friend requests for the authenticated user.
     *
     * Calls `GET /v1/friends/requests/incoming` and maps each entry to a
     * [FriendRequest] that includes the friendship row ID needed to accept
     * or decline the request.
     *
     * @return List of [FriendRequest]s with requester profile data.
     * @throws com.sinura.data.api.ApiException on network or server errors.
     */
    suspend fun getIncomingFriendRequests(): List<FriendRequest>

    /**
     * Accepts or declines a pending friend request.
     *
     * Calls `PATCH /v1/friends/request/{friendshipId}` with the given [accept] flag.
     *
     * @param friendshipId UUID of the friendship row to update.
     * @param accept       `true` to accept, `false` to decline.
     * @return The updated [Friendship] record.
     * @throws com.sinura.data.api.ApiException on network or server errors.
     */
    suspend fun respondToFriendRequest(friendshipId: String, accept: Boolean): Friendship

    /**
     * Returns all confirmed (accepted) friends of the authenticated user.
     *
     * Calls `GET /v1/friends` (default status=accepted).
     *
     * @return List of [Friend]s with basic profile data.
     * @throws com.sinura.data.api.ApiException on network or server errors.
     */
    suspend fun getFriends(): List<Friend>

    /**
     * Removes the friendship between the authenticated user and [friendId].
     *
     * Calls `DELETE /v1/friends/{friendId}`.
     *
     * @param friendId UUID of the friend's user account to remove.
     * @throws com.sinura.data.api.ApiException on network or server errors.
     */
    suspend fun removeFriend(friendId: String)

    /**
     * Returns activity statistics for a specific friend over a given period.
     *
     * Calls `GET /v1/friends/{friendId}/stats?period=<period>`.
     *
     * @param friendId UUID of the friend whose stats are requested.
     * @param period   One of "day", "week", or "month".
     * @return [FriendActivityStats] for the requested period.
     * @throws com.sinura.data.api.ApiException on network or server errors.
     */
    suspend fun getFriendStats(friendId: String, period: String): FriendActivityStats

    suspend fun getFriendMonthlyActivity(friendId: String, month: Int, year: Int): FriendMonthlyActivity

    suspend fun getFriendLevelDetails(friendId: String): FriendLevelDetails
}
