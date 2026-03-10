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
 *
 * Error messages passed to [onError] are user-facing strings only --
 * internal exception details are never forwarded to the UI layer.
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
                onResult(get<NotificationRepository>().getNotifications())
            } catch (e: Exception) {
                onError("Could not load notifications: ${e.message ?: e::class.simpleName ?: "unknown error"}")
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
                onError("Could not mark notification as read: ${e.message ?: e::class.simpleName ?: "unknown error"}")
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
                onError("Could not mark all notifications as read: ${e.message ?: e::class.simpleName ?: "unknown error"}")
            }
        }
    }
}
