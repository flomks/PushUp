package com.pushup.data.repository

import com.pushup.data.api.NotificationApiClient
import com.pushup.domain.model.AppNotification
import com.pushup.domain.repository.NotificationRepository

/**
 * Production implementation of [NotificationRepository].
 *
 * Delegates all operations to [NotificationApiClient] which communicates with
 * the Ktor backend. All calls are already main-safe because Ktor's coroutine
 * dispatcher handles thread switching internally.
 *
 * @property apiClient The HTTP client for notification endpoints.
 */
class NotificationRepositoryImpl(
    private val apiClient: NotificationApiClient,
) : NotificationRepository {

    override suspend fun getNotifications(): List<AppNotification> =
        apiClient.getNotifications()

    override suspend fun markNotificationRead(notificationId: String): Int =
        apiClient.markNotificationRead(notificationId)

    override suspend fun markAllNotificationsRead(): Int =
        apiClient.markAllNotificationsRead()
}
