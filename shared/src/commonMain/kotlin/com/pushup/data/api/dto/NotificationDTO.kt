package com.pushup.data.api.dto

import com.pushup.domain.model.AppNotification
import com.pushup.domain.model.NotificationType
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// ---------------------------------------------------------------------------
// Notification DTOs
// ---------------------------------------------------------------------------

/**
 * DTO for a single entry in the GET /api/notifications response.
 */
@Serializable
data class NotificationDTO(
    val id: String,
    val type: String,
    @SerialName("actorId")   val actorId: String? = null,
    @SerialName("actorName") val actorName: String? = null,
    val payload: String,
    @SerialName("isRead")    val isRead: Boolean,
    @SerialName("createdAt") val createdAt: String,
)

/**
 * DTO for the full GET /api/notifications response body.
 */
@Serializable
data class NotificationsListDTO(
    val notifications: List<NotificationDTO>,
    val total: Int,
    val unreadCount: Int,
)

/**
 * DTO for the PATCH /api/notifications/{id}/read and
 * PATCH /api/notifications/read-all response body.
 */
@Serializable
data class MarkReadResponseDTO(
    val updatedCount: Int,
)

// ---------------------------------------------------------------------------
// Mappers
// ---------------------------------------------------------------------------

fun NotificationDTO.toDomain(): AppNotification = AppNotification(
    id        = id,
    type      = when (type) {
        "friend_request"  -> NotificationType.FRIEND_REQUEST
        "friend_accepted" -> NotificationType.FRIEND_ACCEPTED
        else              -> NotificationType.UNKNOWN
    },
    actorId   = actorId,
    actorName = actorName,
    payload   = payload,
    isRead    = isRead,
    createdAt = createdAt,
)
