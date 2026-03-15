package com.pushup.data.api.dto

import com.pushup.domain.model.Friend
import com.pushup.domain.model.FriendActivityStats
import com.pushup.domain.model.Friendship
import com.pushup.domain.model.FriendRequest
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
 * Request body for PATCH /api/friends/request/{id}.
 */
@Serializable
data class RespondFriendRequestDTO(
    @SerialName("status") val status: String,
)

/**
 * Response body returned by POST /api/friends/request (201 Created)
 * and PATCH /api/friends/request/{id} (200 OK).
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
// Incoming friend requests DTOs
// ---------------------------------------------------------------------------

/**
 * DTO for a single entry in the GET /api/friends/requests/incoming response.
 */
@Serializable
data class IncomingFriendRequestDTO(
    @SerialName("friendshipId") val friendshipId: String,
    @SerialName("requesterId")  val requesterId: String,
    val username: String? = null,
    @SerialName("displayName") val displayName: String? = null,
    @SerialName("avatarUrl")   val avatarUrl: String? = null,
    @SerialName("createdAt")   val createdAt: String,
)

/**
 * DTO for the full GET /api/friends/requests/incoming response body.
 */
@Serializable
data class IncomingFriendRequestsResponseDTO(
    val requests: List<IncomingFriendRequestDTO>,
    val total: Int,
)

// ---------------------------------------------------------------------------
// Friends list DTOs
// ---------------------------------------------------------------------------

/**
 * DTO for a single entry in the GET /api/friends response.
 */
@Serializable
data class FriendProfileDTO(
    val id: String,
    val username: String? = null,
    @SerialName("displayName") val displayName: String? = null,
    @SerialName("avatarUrl")   val avatarUrl: String? = null,
)

/**
 * DTO for the full GET /api/friends response body.
 */
@Serializable
data class FriendsListResponseDTO(
    val friends: List<FriendProfileDTO>,
    val total: Int,
)

// ---------------------------------------------------------------------------
// Friend activity stats DTOs
// ---------------------------------------------------------------------------

/**
 * DTO for the date range in the GET /api/friends/{id}/stats response.
 */
@Serializable
data class FriendStatsDateRangeDTO(
    val from: String,
    val to: String,
)

/**
 * DTO for the GET /api/friends/{id}/stats response body.
 */
@Serializable
data class FriendActivityStatsDTO(
    @SerialName("friendId")           val friendId: String,
    @SerialName("period")             val period: String,
    @SerialName("dateRange")          val dateRange: FriendStatsDateRangeDTO,
    @SerialName("pushupCount")        val pushupCount: Int,
    @SerialName("totalSessions")      val totalSessions: Int,
    @SerialName("totalEarnedSeconds") val totalEarnedSeconds: Long,
    @SerialName("averageQuality")     val averageQuality: Double? = null,
    @SerialName("currentStreak")      val currentStreak: Int = 0,
)

// ---------------------------------------------------------------------------
// Mappers
// ---------------------------------------------------------------------------

fun FriendActivityStatsDTO.toDomain(): FriendActivityStats = FriendActivityStats(
    friendId           = friendId,
    period             = period,
    dateFrom           = dateRange.from,
    dateTo             = dateRange.to,
    pushupCount        = pushupCount,
    totalSessions      = totalSessions,
    totalEarnedSeconds = totalEarnedSeconds,
    averageQuality     = averageQuality,
    currentStreak      = currentStreak,
)

fun FriendProfileDTO.toDomain(): Friend = Friend(
    id          = id,
    username    = username,
    displayName = displayName,
    avatarUrl   = avatarUrl,
)

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

fun IncomingFriendRequestDTO.toDomain(): FriendRequest = FriendRequest(
    friendshipId = friendshipId,
    requesterId  = requesterId,
    username     = username,
    displayName  = displayName,
    avatarUrl    = avatarUrl,
    createdAt    = createdAt,
)
