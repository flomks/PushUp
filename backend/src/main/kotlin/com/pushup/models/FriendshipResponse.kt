package com.pushup.models

import kotlinx.serialization.Serializable

/**
 * Request body for POST /api/friends/request.
 *
 * @property receiverId UUID of the user to whom the friend request is sent.
 */
@Serializable
data class SendFriendRequestBody(
    val receiverId: String,
)

/**
 * Request body for PATCH /api/friends/request/{id}.
 *
 * @property status The desired new status -- must be either "accepted" or "declined".
 */
@Serializable
data class RespondFriendRequestBody(
    val status: String,
)

/**
 * Response body returned by POST /api/friends/request on success (201 Created)
 * and by PATCH /api/friends/request/{id} on success (200 OK).
 *
 * @property id          UUID of the friendship row.
 * @property requesterId UUID of the user who sent the request.
 * @property receiverId  UUID of the user who received the request.
 * @property status      Current status of the friendship ("pending", "accepted", or "declined").
 * @property createdAt   ISO-8601 timestamp when the request was created.
 */
@Serializable
data class FriendshipResponse(
    val id: String,
    val requesterId: String,
    val receiverId: String,
    val status: String,
    val createdAt: String,
)

/**
 * Basic profile data of a friend or pending-request counterpart.
 *
 * Sensitive fields (email, createdAt, updatedAt) are intentionally omitted.
 *
 * @property id          UUID of the user.
 * @property username    Unique handle (e.g. "john_doe"), null if not yet set.
 * @property displayName Free-form display name, null if not yet set.
 * @property avatarUrl   URL to the user's avatar image, null if not set.
 */
@Serializable
data class FriendProfile(
    val id: String,
    val username: String?,
    val displayName: String?,
    val avatarUrl: String?,
)

/**
 * Response body returned by GET /api/friends.
 *
 * @property friends List of friend profiles matching the requested status filter.
 * @property total   Total number of entries in this response (convenience field).
 */
@Serializable
data class FriendsListResponse(
    val friends: List<FriendProfile>,
    val total: Int,
)

/**
 * A single incoming friend request entry, combining the friendship row ID with
 * the requester's profile data.
 *
 * @property friendshipId UUID of the friendship row (used to accept/decline).
 * @property requesterId  UUID of the user who sent the request.
 * @property username     Unique handle of the requester, null if not yet set.
 * @property displayName  Free-form display name of the requester, null if not yet set.
 * @property avatarUrl    URL to the requester's avatar image, null if not set.
 * @property createdAt    ISO-8601 timestamp when the request was created.
 */
@Serializable
data class IncomingFriendRequest(
    val friendshipId: String,
    val requesterId: String,
    val username: String?,
    val displayName: String?,
    val avatarUrl: String?,
    val createdAt: String,
)

/**
 * Response body returned by GET /api/friends/requests/incoming.
 *
 * @property requests List of incoming pending friend requests.
 * @property total    Total number of entries in this response (convenience field).
 */
@Serializable
data class IncomingFriendRequestsResponse(
    val requests: List<IncomingFriendRequest>,
    val total: Int,
)
