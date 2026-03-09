package com.pushup.data.api.dto

import com.pushup.domain.model.Friendship
import com.pushup.domain.model.FriendshipStatus
import com.pushup.domain.model.UserSearchResult
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// ---------------------------------------------------------------------------
// Search DTOs
// ---------------------------------------------------------------------------

/**
 * DTO for a single entry in the GET /api/users/search response.
 */
@Serializable
data class UserSearchResultDTO(
    val id: String,
    val username: String? = null,
    @SerialName("displayName") val displayName: String? = null,
    @SerialName("avatarUrl") val avatarUrl: String? = null,
    @SerialName("friendshipStatus") val friendshipStatus: String,
)

/**
 * DTO for the full GET /api/users/search response body.
 */
@Serializable
data class UserSearchResponseDTO(
    val results: List<UserSearchResultDTO>,
    val total: Int,
)

// ---------------------------------------------------------------------------
// Friendship DTOs
// ---------------------------------------------------------------------------

/**
 * Request body for POST /api/friends/request.
 */
@Serializable
data class SendFriendRequestDTO(
    @SerialName("receiverId") val receiverId: String,
)

/**
 * Response body returned by POST /api/friends/request (201 Created).
 */
@Serializable
data class FriendshipResponseDTO(
    val id: String,
    val requesterId: String,
    val receiverId: String,
    val status: String,
    val createdAt: String,
)

// ---------------------------------------------------------------------------
// Mappers
// ---------------------------------------------------------------------------

fun UserSearchResultDTO.toDomain(): UserSearchResult = UserSearchResult(
    id = id,
    username = username,
    displayName = displayName,
    avatarUrl = avatarUrl,
    friendshipStatus = when (friendshipStatus) {
        "friend"  -> FriendshipStatus.FRIEND
        "pending" -> FriendshipStatus.PENDING
        else      -> FriendshipStatus.NONE
    },
)

fun FriendshipResponseDTO.toDomain(): Friendship = Friendship(
    id = id,
    requesterId = requesterId,
    receiverId = receiverId,
    status = status,
    createdAt = createdAt,
)
