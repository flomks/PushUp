package com.pushup.models

import kotlinx.serialization.Serializable

/**
 * Response body returned by GET /api/me.
 */
@Serializable
data class UserResponse(
    val id: String,
    val email: String,
    val displayName: String?,
    val avatarUrl: String?,
    val createdAt: String,
    val updatedAt: String,
)

/**
 * Generic error response body used across all endpoints.
 */
@Serializable
data class ErrorResponse(
    val error: String,
    val message: String? = null,
)

/**
 * Response body returned by GET /health.
 */
@Serializable
data class HealthResponse(
    val status: String,
)

/**
 * Friendship status of a search result relative to the authenticated user.
 *
 *   none    -- no relationship exists
 *   pending -- a friend request has been sent (in either direction) and is
 *              awaiting a response
 *   friend  -- the request has been accepted; both users are friends
 */
@Serializable
enum class FriendshipStatusResponse {
    none,
    pending,
    friend,
}

/**
 * A single entry in the user-search result list.
 *
 * Sensitive fields (email, createdAt, updatedAt) are intentionally omitted.
 * The [friendshipStatus] field reflects the relationship between the
 * authenticated caller and this user.
 *
 * @property id               UUID of the user.
 * @property username         Unique handle (e.g. "john_doe"), null if not yet set.
 * @property displayName      Free-form display name, null if not yet set.
 * @property avatarUrl        URL to the user's avatar image, null if not set.
 * @property friendshipStatus Relationship between the caller and this user.
 */
@Serializable
data class UserSearchResult(
    val id: String,
    val username: String?,
    val displayName: String?,
    val avatarUrl: String?,
    val friendshipStatus: FriendshipStatusResponse,
)

/**
 * Response body returned by GET /api/users/search.
 *
 * @property results  Ordered list of matching users (max 20 entries).
 * @property total    Total number of results in this response (convenience field).
 */
@Serializable
data class UserSearchResponse(
    val results: List<UserSearchResult>,
    val total: Int,
)
