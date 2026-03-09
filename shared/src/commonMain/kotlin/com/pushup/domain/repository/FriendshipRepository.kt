package com.pushup.domain.repository

import com.pushup.domain.model.Friendship
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
}
