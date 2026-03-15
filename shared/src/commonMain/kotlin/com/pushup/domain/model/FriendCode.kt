package com.pushup.domain.model

/**
 * Privacy setting for a friend code.
 *
 * Controls what happens when another user enters or scans the code:
 *   AUTO_ACCEPT      -- the caller is added as a friend immediately
 *   REQUIRE_APPROVAL -- a pending friend request is created; the owner must accept
 *   INACTIVE         -- the code is disabled; no action is taken
 */
enum class FriendCodePrivacy {
    AUTO_ACCEPT,
    REQUIRE_APPROVAL,
    INACTIVE,
}

/**
 * The authenticated user's own friend code.
 *
 * @property code      Short alphanumeric code (e.g. "AB3X7K2M").
 * @property privacy   Current privacy setting.
 * @property deepLink  Deep-link URL that opens the app and pre-fills the code.
 * @property createdAt ISO-8601 timestamp when the code was first generated.
 * @property updatedAt ISO-8601 timestamp of the last change.
 */
data class FriendCode(
    val code: String,
    val privacy: FriendCodePrivacy,
    val deepLink: String,
    val createdAt: String,
    val updatedAt: String,
)

/**
 * Result of using a friend code.
 *
 * @property result       "added" (auto-accepted) or "pending" (request sent).
 * @property ownerProfile Basic profile of the code owner.
 * @property friendship   The created friendship or pending request record.
 */
data class UseFriendCodeResult(
    val result: String,
    val ownerProfile: Friend,
    val friendship: Friendship,
)
