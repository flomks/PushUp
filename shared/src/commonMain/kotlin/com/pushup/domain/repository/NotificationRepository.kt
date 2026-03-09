package com.pushup.domain.repository

import com.pushup.domain.model.AppNotification

/**
 * Repository for in-app notifications.
 *
 * All implementations must be **main-safe** -- dispatcher switching is handled internally.
 */
interface NotificationRepository {

    /**
     * Returns all in-app notifications for the authenticated user, ordered
     * by creation time descending (newest first).
     *
     * Calls `GET /api/notifications`.
     *
     * @return List of [AppNotification]s.
     * @throws com.pushup.data.api.ApiException on network or server errors.
     */
    suspend fun getNotifications(): List<AppNotification>

    /**
     * Marks a single notification as read.
     *
     * Calls `PATCH /api/notifications/{notificationId}/read`.
     *
     * @param notificationId UUID of the notification to mark as read.
     * @return Number of notifications updated (0 or 1).
     * @throws com.pushup.data.api.ApiException on network or server errors.
     */
    suspend fun markNotificationRead(notificationId: String): Int

    /**
     * Marks all unread notifications for the authenticated user as read.
     *
     * Calls `PATCH /api/notifications/read-all`.
     *
     * @return Number of notifications updated.
     * @throws com.pushup.data.api.ApiException on network or server errors.
     */
    suspend fun markAllNotificationsRead(): Int
}
