package com.pushup.service

import com.pushup.models.MarkReadResponse
import com.pushup.models.NotificationResponse
import com.pushup.models.NotificationsListResponse
import com.pushup.plugins.Notifications
import com.pushup.plugins.Users
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.and
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import org.jetbrains.exposed.sql.update
import java.time.format.DateTimeFormatter
import java.util.UUID

/**
 * Result type for [NotificationService.markNotificationRead].
 */
sealed class MarkNotificationReadResult {
    /** The notification was marked as read successfully. */
    data class Success(val response: MarkReadResponse) : MarkNotificationReadResult()

    /** No notification with the given ID exists for this user. */
    object NotFound : MarkNotificationReadResult()
}

/**
 * Business logic for the notifications feature.
 *
 * All database access is performed inside [newSuspendedTransaction] so that
 * Ktor's coroutine event loop is not blocked.
 *
 * The class and its public methods are `open` so that tests can create stub
 * subclasses without requiring a mocking framework.
 */
open class NotificationService {

    /**
     * Returns all notifications for [userId], ordered by creation time descending
     * (newest first).
     *
     * Each notification is enriched with the actor's display name or username
     * (whichever is available) via a join on the users table.
     *
     * @param userId UUID of the authenticated caller.
     * @return [NotificationsListResponse] with all notifications and unread count.
     */
    open suspend fun getNotifications(
        userId: UUID,
    ): NotificationsListResponse = newSuspendedTransaction {

        val rows = Notifications.selectAll()
            .where { Notifications.userId eq userId }
            .orderBy(Notifications.createdAt, org.jetbrains.exposed.sql.SortOrder.DESC)
            .toList()

        if (rows.isEmpty()) {
            return@newSuspendedTransaction NotificationsListResponse(
                notifications = emptyList(),
                total         = 0,
                unreadCount   = 0,
            )
        }

        // Collect all actor UUIDs for a single batch profile lookup.
        val actorIds = rows.mapNotNull { it[Notifications.actorId] }.distinct()

        val actorNamesById: Map<UUID, String?> = if (actorIds.isEmpty()) {
            emptyMap()
        } else {
            Users.selectAll()
                .where { Users.id inList actorIds }
                .associate { userRow ->
                    val id = userRow[Users.id]
                    val name = userRow[Users.displayName] ?: userRow[Users.username]
                    id to name
                }
        }

        val notifications: List<NotificationResponse> = rows.map { row ->
            val actorId = row[Notifications.actorId]
            NotificationResponse(
                id        = row[Notifications.id].toString(),
                type      = row[Notifications.type],
                actorId   = actorId?.toString(),
                actorName = actorId?.let { actorNamesById[it] },
                payload   = row[Notifications.payload],
                isRead    = row[Notifications.isRead],
                createdAt = row[Notifications.createdAt]
                    .format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
            )
        }

        val unreadCount = notifications.count { !it.isRead }

        NotificationsListResponse(
            notifications = notifications,
            total         = notifications.size,
            unreadCount   = unreadCount,
        )
    }

    /**
     * Marks a single notification as read.
     *
     * Only the owner of the notification (the user whose [userId] matches
     * [Notifications.userId]) may mark it as read.
     *
     * @param userId         UUID of the authenticated caller.
     * @param notificationId UUID of the notification to mark as read.
     * @return [MarkNotificationReadResult] describing the outcome.
     */
    open suspend fun markNotificationRead(
        userId: UUID,
        notificationId: UUID,
    ): MarkNotificationReadResult = newSuspendedTransaction {

        // Verify the notification exists and belongs to this user.
        val exists = Notifications.selectAll()
            .where {
                (Notifications.id eq notificationId) and
                (Notifications.userId eq userId)
            }
            .count() > 0

        if (!exists) {
            return@newSuspendedTransaction MarkNotificationReadResult.NotFound
        }

        val updated = Notifications.update({
            (Notifications.id eq notificationId) and
            (Notifications.userId eq userId) and
            (Notifications.isRead eq false)
        }) {
            it[isRead] = true
        }

        MarkNotificationReadResult.Success(MarkReadResponse(updatedCount = updated))
    }

    /**
     * Marks all unread notifications for [userId] as read.
     *
     * @param userId UUID of the authenticated caller.
     * @return [MarkReadResponse] with the number of notifications updated.
     */
    open suspend fun markAllNotificationsRead(
        userId: UUID,
    ): MarkReadResponse = newSuspendedTransaction {

        val updated = Notifications.update({
            (Notifications.userId eq userId) and
            (Notifications.isRead eq false)
        }) {
            it[isRead] = true
        }

        MarkReadResponse(updatedCount = updated)
    }
}
