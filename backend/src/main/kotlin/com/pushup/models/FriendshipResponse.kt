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
 * Response body returned by POST /api/friends/request on success (201 Created).
 *
 * @property id          UUID of the newly created friendship row.
 * @property requesterId UUID of the user who sent the request (the caller).
 * @property receiverId  UUID of the user who received the request.
 * @property status      Current status of the friendship -- always "pending" on creation.
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
