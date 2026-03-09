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
