package com.sinura.domain.model

/**
 * A confirmed friend of the authenticated user.
 *
 * Returned by GET /api/friends (status=accepted).
 *
 * @property id          UUID of the friend's user account.
 * @property username    Unique handle (e.g. "john_doe"), null if not yet set.
 * @property displayName Free-form display name, null if not yet set.
 * @property avatarUrl   URL to the friend's avatar image, null if not set.
 */
data class Friend(
    val id: String,
    val username: String?,
    val displayName: String?,
    val avatarUrl: String?,
)

/**
 * Represents the friendship status between the authenticated user and another user.
 */
enum class FriendshipStatus {
    /** No relationship exists. */
    NONE,

    /** A friend request has been sent (in either direction) and is awaiting a response. */
    PENDING,

    /** The request has been accepted; both users are friends. */
    FRIEND,
}

/**
 * A user returned from the search endpoint, annotated with the friendship status
 * relative to the authenticated caller.
 *
 * @property id               UUID of the user.
 * @property username         Unique handle (e.g. "john_doe"), null if not yet set.
 * @property displayName      Free-form display name, null if not yet set.
 * @property avatarUrl        URL to the user's avatar image, null if not set.
 * @property friendshipStatus Relationship between the caller and this user.
 */
data class UserSearchResult(
    val id: String,
    val username: String?,
    val displayName: String?,
    val avatarUrl: String?,
    val friendshipStatus: FriendshipStatus,
)

/**
 * Represents a friendship record returned after sending or responding to a friend request.
 *
 * @property id          UUID of the friendship row.
 * @property requesterId UUID of the user who sent the request.
 * @property receiverId  UUID of the user who received the request.
 * @property status      Current status: "pending", "accepted", or "declined".
 * @property createdAt   ISO-8601 timestamp when the request was created.
 */
data class Friendship(
    val id: String,
    val requesterId: String,
    val receiverId: String,
    val status: String,
    val createdAt: String,
)

/**
 * Represents an incoming pending friend request shown in the inbox.
 *
 * @property friendshipId UUID of the friendship row (used to accept/decline).
 * @property requesterId  UUID of the user who sent the request.
 * @property username     Unique handle of the requester, null if not yet set.
 * @property displayName  Free-form display name of the requester, null if not yet set.
 * @property avatarUrl    URL to the requester's avatar image, null if not set.
 * @property createdAt    ISO-8601 timestamp when the request was created.
 */
data class FriendRequest(
    val friendshipId: String,
    val requesterId: String,
    val username: String?,
    val displayName: String?,
    val avatarUrl: String?,
    val createdAt: String,
)
