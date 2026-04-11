package com.sinura.data.api.dto

import com.sinura.domain.model.FriendCode
import com.sinura.domain.model.FriendCodePrivacy
import com.sinura.domain.model.UseFriendCodeResult
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// ---------------------------------------------------------------------------
// Request DTOs
// ---------------------------------------------------------------------------

/**
 * Request body for PATCH /v1/friend-code/privacy.
 */
@Serializable
data class UpdateFriendCodePrivacyDTO(
    @SerialName("privacy") val privacy: String,
)

/**
 * Request body for POST /v1/friend-code/use.
 */
@Serializable
data class UseFriendCodeRequestDTO(
    @SerialName("code") val code: String,
)

// ---------------------------------------------------------------------------
// Response DTOs
// ---------------------------------------------------------------------------

/**
 * Response body returned by GET /v1/friend-code and POST /v1/friend-code/reset.
 */
@Serializable
data class FriendCodeResponseDTO(
    @SerialName("code")      val code: String,
    @SerialName("privacy")   val privacy: String,
    @SerialName("deepLink")  val deepLink: String,
    @SerialName("createdAt") val createdAt: String,
    @SerialName("updatedAt") val updatedAt: String,
)

/**
 * Response body returned by POST /v1/friend-code/use.
 */
@Serializable
data class UseFriendCodeResponseDTO(
    @SerialName("result")       val result: String,
    @SerialName("ownerProfile") val ownerProfile: FriendProfileDTO,
    @SerialName("friendship")   val friendship: FriendshipResponseDTO,
)

// ---------------------------------------------------------------------------
// Mappers
// ---------------------------------------------------------------------------

fun FriendCodeResponseDTO.toDomain(): FriendCode = FriendCode(
    code      = code,
    privacy   = when (privacy) {
        "auto_accept"      -> FriendCodePrivacy.AUTO_ACCEPT
        "inactive"         -> FriendCodePrivacy.INACTIVE
        else               -> FriendCodePrivacy.REQUIRE_APPROVAL
    },
    deepLink  = deepLink,
    createdAt = createdAt,
    updatedAt = updatedAt,
)

fun UseFriendCodeResponseDTO.toDomain(): UseFriendCodeResult = UseFriendCodeResult(
    result       = result,
    ownerProfile = ownerProfile.toDomain(),
    friendship   = friendship.toDomain(),
)
