package com.pushup.domain.repository

import com.pushup.domain.model.Friendship
import com.pushup.domain.model.FriendRequest
import com.pushup.domain.model.UserSearchResult

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
     * @throws com.pushup.data.api.ApiException on network or server errors.
     */
    suspend fun searchUsers(query: String): List<UserSearchResult>

    /**
     * Sends a friend request from the authenticated user to [receiverId].
     *
     * @param receiverId UUID of the user to send the request to.
     * @return The created [Friendship] record.
     * @throws com.pushup.data.api.ApiException on network or server errors.
     */
    suspend fun sendFriendRequest(receiverId: String): Friendship

    /**
     * Returns all incoming pending friend requests for the authenticated user.
     *
     * Calls `GET /api/friends/requests/incoming` and maps each entry to a
     * [FriendRequest] that includes the friendship row ID needed to accept
     * or decline the request.
     *
     * @return List of [FriendRequest]s with requester profile data.
     * @throws com.pushup.data.api.ApiException on network or server errors.
     */
    suspend fun getIncomingFriendRequests(): List<FriendRequest>

    /**
     * Accepts or declines a pending friend request.
     *
     * Calls `PATCH /api/friends/request/{friendshipId}` with the given [accept] flag.
     *
     * @param friendshipId UUID of the friendship row to update.
     * @param accept       `true` to accept, `false` to decline.
     * @return The updated [Friendship] record.
     * @throws com.pushup.data.api.ApiException on network or server errors.
     */
    suspend fun respondToFriendRequest(friendshipId: String, accept: Boolean): Friendship
}
