package com.sinura.models

import kotlinx.serialization.Serializable

// ---------------------------------------------------------------------------
// Request bodies
// ---------------------------------------------------------------------------

/**
 * Request body for PATCH /v1/friend-code/privacy.
 *
 * @property privacy One of "auto_accept", "require_approval", or "inactive".
 */
@Serializable
data class UpdateFriendCodePrivacyRequest(
    val privacy: String,
)

// ---------------------------------------------------------------------------
// Response bodies
// ---------------------------------------------------------------------------

/**
 * Response body returned by GET /v1/friend-code and POST /v1/friend-code/reset.
 *
 * @property code      The short alphanumeric friend code (e.g. "AB3X7K2M").
 * @property privacy   Current privacy setting: "auto_accept", "require_approval", or "inactive".
 * @property deepLink  A deep-link URL that opens the app and pre-fills the code.
 * @property createdAt ISO-8601 timestamp when the code was first generated.
 * @property updatedAt ISO-8601 timestamp of the last change.
 */
@Serializable
data class FriendCodeResponse(
    val code: String,
    val privacy: String,
    val deepLink: String,
    val createdAt: String,
    val updatedAt: String,
)

/**
 * Request body for POST /v1/friend-code/use.
 *
 * @property code The friend code to use.
 */
@Serializable
data class UseFriendCodeRequest(
    val code: String,
)

/**
 * Response body returned by POST /v1/friend-code/use.
 *
 * @property result       One of "added" (auto-accepted) or "pending" (request sent).
 * @property ownerProfile Basic profile of the code owner.
 * @property friendship   The created friendship or pending request record.
 */
@Serializable
data class UseFriendCodeResponse(
    val result: String,
    val ownerProfile: FriendProfile,
    val friendship: FriendshipResponse,
)
