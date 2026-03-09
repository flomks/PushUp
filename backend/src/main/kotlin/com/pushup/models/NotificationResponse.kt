package com.pushup.models

import kotlinx.serialization.Serializable

/**
 * A single in-app notification returned by GET /api/notifications.
 *
 * @property id        UUID of the notification row.
 * @property type      Notification type: "friend_request" or "friend_accepted".
 * @property actorId   UUID of the user who triggered the notification, null if deleted.
 * @property actorName Display name or username of the actor, null if not available.
 * @property payload   Arbitrary JSON metadata (e.g. friendship_id).
 * @property isRead    Whether the recipient has read/dismissed this notification.
 * @property createdAt ISO-8601 timestamp when the notification was created.
 */
@Serializable
data class NotificationResponse(
    val id: String,
    val type: String,
    val actorId: String?,
    val actorName: String?,
    val payload: String,
    val isRead: Boolean,
    val createdAt: String,
)

/**
 * Response body returned by GET /api/notifications.
 *
 * @property notifications List of notifications for the authenticated user.
 * @property total         Total number of notifications in this response.
 * @property unreadCount   Number of unread notifications.
 */
@Serializable
data class NotificationsListResponse(
    val notifications: List<NotificationResponse>,
    val total: Int,
    val unreadCount: Int,
)

/**
 * Response body returned by PATCH /api/notifications/{id}/read and
 * PATCH /api/notifications/read-all.
 *
 * @property updatedCount Number of notifications that were marked as read.
 */
@Serializable
data class MarkReadResponse(
    val updatedCount: Int,
)
