package com.flomks.pushup.notifications

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pushup.data.api.ApiException
import com.pushup.domain.model.AppNotification
import com.pushup.domain.repository.NotificationRepository
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

/**
 * Represents the state of the notification center screen.
 *
 * @property listState          Current loading / content / error state.
 * @property unreadCount        Number of unread notifications (used for badge).
 * @property markReadInFlightIds Set of notification IDs for which a mark-read
 *                              call is currently in flight.
 * @property actionError        Transient error message shown when a mark-read
 *                              action fails.
 * @property newNotificationBanner A transient banner notification to show as an
 *                              in-app banner (e.g. when a new notification arrives
 *                              while the user is in the app). Cleared after display.
 */
data class NotificationUiState(
    val listState: NotificationListState = NotificationListState.Loading,
    val unreadCount: Int = 0,
    val markReadInFlightIds: Set<String> = emptySet(),
    val actionError: String? = null,
    val newNotificationBanner: AppNotification? = null,
)

/**
 * Represents the possible states of the notification list.
 */
sealed interface NotificationListState {
    /** Initial load is in progress. */
    data object Loading : NotificationListState

    /** Loaded successfully with at least one notification. */
    data class Success(val notifications: List<AppNotification>) : NotificationListState

    /** Loaded successfully but there are no notifications. */
    data object Empty : NotificationListState

    /** Load failed with an error message. */
    data class Error(val message: String) : NotificationListState
}

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * ViewModel for the notification center screen.
 *
 * Handles:
 * - Loading the list of notifications on creation.
 * - Marking individual notifications as read.
 * - Marking all notifications as read (badge reset).
 * - Tracking the unread count for the badge.
 * - Error state management with user-visible feedback.
 *
 * @property repository The [NotificationRepository] used for API calls.
 */
class NotificationViewModel(
    private val repository: NotificationRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(NotificationUiState())
    val uiState: StateFlow<NotificationUiState> = _uiState.asStateFlow()

    /** Tracks the currently running load so it can be cancelled on refresh. */
    private var activeLoadJob: Job? = null

    init {
        loadNotifications()
    }

    // -------------------------------------------------------------------------
    // Public events
    // -------------------------------------------------------------------------

    /**
     * Reloads the notification list from the server.
     *
     * Cancels any in-flight load to prevent stale results from overwriting
     * the new response.
     */
    fun onRefresh() {
        loadNotifications()
    }

    /**
     * Marks the notification identified by [notificationId] as read.
     *
     * Optimistically updates the notification in the list on success.
     * On error, surfaces a transient error message.
     */
    fun onMarkRead(notificationId: String) {
        if (_uiState.value.markReadInFlightIds.contains(notificationId)) return

        viewModelScope.launch {
            _uiState.update { state ->
                state.copy(
                    markReadInFlightIds = state.markReadInFlightIds + notificationId,
                    actionError = null,
                )
            }

            try {
                repository.markNotificationRead(notificationId)
                markNotificationReadInList(notificationId)
            } catch (e: ApiException.Unauthorized) {
                _uiState.update { state ->
                    state.copy(
                        markReadInFlightIds = state.markReadInFlightIds - notificationId,
                        actionError = "Session expired. Please log in again.",
                    )
                }
            } catch (e: Exception) {
                _uiState.update { state ->
                    state.copy(
                        markReadInFlightIds = state.markReadInFlightIds - notificationId,
                        actionError = "Failed to mark notification as read. Please try again.",
                    )
                }
            }
        }
    }

    /**
     * Marks all unread notifications as read.
     *
     * Optimistically updates all notifications in the list and resets the
     * badge counter to zero.
     */
    fun onMarkAllRead() {
        viewModelScope.launch {
            try {
                repository.markAllNotificationsRead()
                markAllNotificationsReadInList()
            } catch (e: ApiException.Unauthorized) {
                _uiState.update { state ->
                    state.copy(actionError = "Session expired. Please log in again.")
                }
            } catch (e: Exception) {
                _uiState.update { state ->
                    state.copy(actionError = "Failed to mark notifications as read. Please try again.")
                }
            }
        }
    }

    /**
     * Dismisses the transient action error message.
     */
    fun onDismissActionError() {
        _uiState.update { it.copy(actionError = null) }
    }

    /**
     * Dismisses the in-app notification banner.
     */
    fun onDismissBanner() {
        _uiState.update { it.copy(newNotificationBanner = null) }
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /**
     * Fetches the notification list and updates [_uiState].
     *
     * Cancels any previously running load to avoid stale results overwriting
     * newer ones when the user taps refresh rapidly.
     *
     * After loading, compares the new list with the previous one to detect
     * newly arrived notifications and surface them as an in-app banner.
     */
    private fun loadNotifications() {
        activeLoadJob?.cancel()
        activeLoadJob = viewModelScope.launch {
            _uiState.update { it.copy(listState = NotificationListState.Loading) }
            try {
                val notifications = repository.getNotifications()
                val unreadCount = notifications.count { !it.isRead }

                // Detect a newly arrived unread notification to show as a banner.
                // We show the most recent unread notification if the previous state
                // had fewer unread items (i.e. a new one arrived since last load).
                val previousUnread = _uiState.value.unreadCount
                val banner: AppNotification? = if (unreadCount > previousUnread) {
                    notifications.firstOrNull { !it.isRead }
                } else {
                    null
                }

                _uiState.update {
                    it.copy(
                        listState = if (notifications.isEmpty()) {
                            NotificationListState.Empty
                        } else {
                            NotificationListState.Success(notifications)
                        },
                        unreadCount = unreadCount,
                        newNotificationBanner = banner ?: it.newNotificationBanner,
                    )
                }
            } catch (e: ApiException.Unauthorized) {
                _uiState.update {
                    it.copy(listState = NotificationListState.Error("Session expired. Please log in again."))
                }
            } catch (e: ApiException) {
                _uiState.update {
                    it.copy(listState = NotificationListState.Error("Failed to load notifications. Please try again."))
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(listState = NotificationListState.Error("An unexpected error occurred."))
                }
            }
        }
    }

    /**
     * Optimistically marks a single notification as read in the current list
     * and decrements the unread count.
     */
    private fun markNotificationReadInList(notificationId: String) {
        _uiState.update { state ->
            val updatedNotifications = (state.listState as? NotificationListState.Success)
                ?.notifications
                ?.map { notification ->
                    if (notification.id == notificationId) {
                        notification.copy(isRead = true)
                    } else {
                        notification
                    }
                }

            val newListState = when {
                updatedNotifications == null -> state.listState
                else                         -> NotificationListState.Success(updatedNotifications)
            }

            val newUnreadCount = (updatedNotifications ?: emptyList()).count { !it.isRead }

            state.copy(
                listState           = newListState,
                unreadCount         = newUnreadCount,
                markReadInFlightIds = state.markReadInFlightIds - notificationId,
            )
        }
    }

    /**
     * Optimistically marks all notifications as read in the current list
     * and resets the unread count to zero.
     */
    private fun markAllNotificationsReadInList() {
        _uiState.update { state ->
            val updatedNotifications = (state.listState as? NotificationListState.Success)
                ?.notifications
                ?.map { it.copy(isRead = true) }

            val newListState = when {
                updatedNotifications == null -> state.listState
                else                         -> NotificationListState.Success(updatedNotifications)
            }

            state.copy(
                listState   = newListState,
                unreadCount = 0,
            )
        }
    }
}
