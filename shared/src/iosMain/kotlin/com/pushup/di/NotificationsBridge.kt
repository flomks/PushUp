package com.pushup.di

import com.pushup.domain.model.AppNotification
import com.pushup.domain.repository.NotificationRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.get

/**
 * iOS-facing bridge that exposes in-app notification operations to Swift.
 *
 * All callbacks are dispatched on [Dispatchers.Main] so Swift ViewModels
 * can update @Published properties directly.
 */
object NotificationsBridge : KoinComponent {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // =========================================================================
    // Fetch notifications
    // =========================================================================

    fun getNotifications(
        onResult: (List<AppNotification>) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val notifications = get<NotificationRepository>().getNotifications()
                onResult(notifications)
            } catch (e: Exception) {
                onError(e.message ?: "Failed to load notifications")
            }
        }
    }

    // =========================================================================
    // Mark single notification as read
    // =========================================================================

    fun markNotificationRead(
        notificationId: String,
        onSuccess: () -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                get<NotificationRepository>().markNotificationRead(notificationId)
                onSuccess()
            } catch (e: Exception) {
                onError(e.message ?: "Failed to mark as read")
            }
        }
    }

    // =========================================================================
    // Mark all notifications as read
    // =========================================================================

    fun markAllNotificationsRead(
        onSuccess: () -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                get<NotificationRepository>().markAllNotificationsRead()
                onSuccess()
            } catch (e: Exception) {
                onError(e.message ?: "Failed to mark all as read")
            }
        }
    }
}
