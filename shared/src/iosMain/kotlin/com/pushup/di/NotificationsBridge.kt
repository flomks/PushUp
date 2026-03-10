package com.pushup.di

import com.pushup.domain.model.AppNotification
import com.pushup.domain.repository.NotificationRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.koin.core.component.KoinComponent
import org.koin.core.component.get

/**
 * iOS-facing bridge that exposes in-app notification operations to Swift.
 *
 * Network/IO work runs on [Dispatchers.Default] to keep the main thread free.
 * All callbacks are dispatched back on [Dispatchers.Main] so Swift ViewModels
 * can update @Published properties directly without DispatchQueue.main.async.
 *
 * Error messages passed to [onError] are user-facing strings only --
 * internal exception details are never forwarded to the UI layer.
 */
object NotificationsBridge : KoinComponent {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

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
                withContext(Dispatchers.Main) { onResult(notifications) }
            } catch (e: Exception) {
                val msg = "Could not load notifications: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
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
                withContext(Dispatchers.Main) { onSuccess() }
            } catch (e: Exception) {
                val msg = "Could not mark notification as read: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
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
                withContext(Dispatchers.Main) { onSuccess() }
            } catch (e: Exception) {
                val msg = "Could not mark all notifications as read: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }
}
