package com.pushup.domain.model

/**
 * The type of an in-app notification.
 */
enum class NotificationType {
    /** A user sent a friend request to the recipient. */
    FRIEND_REQUEST,

    /** The recipient's friend request was accepted. */
    FRIEND_ACCEPTED,

    /** An unknown notification type received from the server. */
    UNKNOWN,
}

/**
 * An in-app notification for the authenticated user.
 *
 * @property id        UUID of the notification row.
 * @property type      Parsed notification type.
 * @property actorId   UUID of the user who triggered the notification, null if deleted.
 * @property actorName Display name or username of the actor, null if not available.
 * @property payload   Raw JSON metadata string (e.g. `{"friendship_id":"<uuid>"}`).
 * @property isRead    Whether the recipient has read/dismissed this notification.
 * @property createdAt ISO-8601 timestamp when the notification was created.
 */
data class AppNotification(
    val id: String,
    val type: NotificationType,
    val actorId: String?,
    val actorName: String?,
    val payload: String,
    val isRead: Boolean,
    val createdAt: String,
)
