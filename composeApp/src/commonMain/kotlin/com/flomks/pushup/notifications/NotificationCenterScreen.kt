package com.flomks.pushup.notifications

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.pushup.domain.model.AppNotification
import com.pushup.domain.model.NotificationType

// ---------------------------------------------------------------------------
// Screen entry point
// ---------------------------------------------------------------------------

/**
 * Full notification center screen.
 *
 * Observes [viewModel] state and delegates all events back to it.
 */
@Composable
fun NotificationCenterScreen(
    viewModel: NotificationViewModel,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()

    NotificationCenterContent(
        uiState              = uiState,
        onMarkRead           = viewModel::onMarkRead,
        onMarkAllRead        = viewModel::onMarkAllRead,
        onRefresh            = viewModel::onRefresh,
        onDismissActionError = viewModel::onDismissActionError,
        onDismissBanner      = viewModel::onDismissBanner,
        modifier             = modifier,
    )
}

// ---------------------------------------------------------------------------
// Stateless content (testable / previewable)
// ---------------------------------------------------------------------------

@Composable
internal fun NotificationCenterContent(
    uiState: NotificationUiState,
    onMarkRead: (String) -> Unit,
    onMarkAllRead: () -> Unit,
    onRefresh: () -> Unit,
    onDismissActionError: () -> Unit = {},
    onDismissBanner: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
    ) {
        Spacer(modifier = Modifier.height(16.dp))

        // Title row with "Mark all read" button
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = "Notifications",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )

            if (uiState.unreadCount > 0) {
                TextButton(onClick = onMarkAllRead) {
                    Icon(
                        imageVector = Icons.Default.Check,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "Mark all read",
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
        }

        // In-app banner for newly arrived notification
        val banner = uiState.newNotificationBanner
        if (banner != null) {
            Spacer(modifier = Modifier.height(8.dp))
            NotificationBanner(
                notification = banner,
                onDismiss    = onDismissBanner,
                onMarkRead   = { onMarkRead(banner.id) },
            )
        }

        // Transient error banner for failed mark-read actions
        if (uiState.actionError != null) {
            Spacer(modifier = Modifier.height(8.dp))
            ActionErrorBanner(
                message   = uiState.actionError,
                onDismiss = onDismissActionError,
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        when (val state = uiState.listState) {
            is NotificationListState.Loading -> NotificationLoadingState()
            is NotificationListState.Empty   -> NotificationEmptyState()
            is NotificationListState.Error   -> NotificationErrorState(
                message = state.message,
                onRetry = onRefresh,
            )
            is NotificationListState.Success -> NotificationList(
                notifications       = state.notifications,
                markReadInFlightIds = uiState.markReadInFlightIds,
                onMarkRead          = onMarkRead,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// In-app notification banner
// ---------------------------------------------------------------------------

/**
 * A dismissible in-app banner shown when a new notification arrives while
 * the user is actively using the app.
 *
 * Displayed at the top of the notification center (below the title) so it
 * does not obscure the list content.
 */
@Composable
private fun NotificationBanner(
    notification: AppNotification,
    onDismiss: () -> Unit,
    onMarkRead: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
        ),
        shape = RoundedCornerShape(12.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = notificationIcon(notification.type),
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            Spacer(modifier = Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = notificationTitle(notification),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = notificationBody(notification),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            IconButton(
                onClick = {
                    onMarkRead()
                    onDismiss()
                },
                modifier = Modifier.size(32.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = "Dismiss",
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Action error banner
// ---------------------------------------------------------------------------

/**
 * Dismissible error banner shown when a mark-read action fails.
 */
@Composable
private fun ActionErrorBanner(
    message: String,
    onDismiss: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Default.Warning,
            contentDescription = null,
            modifier = Modifier.size(16.dp),
            tint = MaterialTheme.colorScheme.error,
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = message,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error,
        )
        TextButton(onClick = onDismiss) {
            Text(text = "Dismiss", style = MaterialTheme.typography.labelSmall)
        }
    }
}

// ---------------------------------------------------------------------------
// Empty / loading / error states
// ---------------------------------------------------------------------------

@Composable
private fun NotificationLoadingState() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator()
    }
}

@Composable
private fun NotificationEmptyState() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.Notifications,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "No notifications",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "You have no notifications yet",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            )
        }
    }
}

@Composable
private fun NotificationErrorState(
    message: String,
    onRetry: () -> Unit,
) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.error.copy(alpha = 0.7f),
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.error,
            )
            Spacer(modifier = Modifier.height(16.dp))
            TextButton(onClick = onRetry) {
                Text(text = "Retry")
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Notification list
// ---------------------------------------------------------------------------

@Composable
private fun NotificationList(
    notifications: List<AppNotification>,
    markReadInFlightIds: Set<String>,
    onMarkRead: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(modifier = modifier) {
        items(
            items = notifications,
            key = { it.id },
        ) { notification ->
            NotificationItem(
                notification        = notification,
                isMarkReadInFlight  = markReadInFlightIds.contains(notification.id),
                onMarkRead          = { onMarkRead(notification.id) },
            )
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Single notification row
// ---------------------------------------------------------------------------

@Composable
private fun NotificationItem(
    notification: AppNotification,
    isMarkReadInFlight: Boolean,
    onMarkRead: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isUnread = !notification.isRead

    Row(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (isUnread) {
                    Modifier.background(
                        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.15f),
                    )
                } else {
                    Modifier
                }
            )
            .clickable(enabled = isUnread && !isMarkReadInFlight) { onMarkRead() }
            .padding(vertical = 12.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Unread indicator dot
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(RoundedCornerShape(50))
                .background(
                    color = if (isUnread) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f)
                    },
                ),
        )

        Spacer(modifier = Modifier.width(12.dp))

        // Notification type icon
        Icon(
            imageVector = notificationIcon(notification.type),
            contentDescription = null,
            modifier = Modifier.size(24.dp),
            tint = if (isUnread) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
            },
        )

        Spacer(modifier = Modifier.width(12.dp))

        // Notification text
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = notificationTitle(notification),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = if (isUnread) FontWeight.SemiBold else FontWeight.Normal,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = notificationBody(notification),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }

        // Mark-read spinner or tap hint
        if (isMarkReadInFlight) {
            Spacer(modifier = Modifier.width(8.dp))
            CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                strokeWidth = 2.dp,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Notification content helpers
// ---------------------------------------------------------------------------

/**
 * Returns the icon for a given [NotificationType].
 */
private fun notificationIcon(type: NotificationType) = when (type) {
    NotificationType.FRIEND_REQUEST  -> Icons.Default.PersonAdd
    NotificationType.FRIEND_ACCEPTED -> Icons.Default.Check
    NotificationType.UNKNOWN         -> Icons.Default.Notifications
}

/**
 * Returns a short title string for a notification.
 */
private fun notificationTitle(notification: AppNotification): String =
    when (notification.type) {
        NotificationType.FRIEND_REQUEST  -> "New friend request"
        NotificationType.FRIEND_ACCEPTED -> "Friend request accepted"
        NotificationType.UNKNOWN         -> "New notification"
    }

/**
 * Returns a descriptive body string for a notification.
 */
private fun notificationBody(notification: AppNotification): String {
    val actor = notification.actorName ?: "Someone"
    return when (notification.type) {
        NotificationType.FRIEND_REQUEST  -> "$actor sent you a friend request"
        NotificationType.FRIEND_ACCEPTED -> "$actor accepted your friend request"
        NotificationType.UNKNOWN         -> "You have a new notification"
    }
}

// ---------------------------------------------------------------------------
// Preview
// ---------------------------------------------------------------------------

@Preview
@Composable
private fun NotificationCenterPreview() {
    MaterialTheme {
        Surface {
            NotificationCenterContent(
                uiState = NotificationUiState(
                    listState = NotificationListState.Success(
                        notifications = listOf(
                            AppNotification(
                                id        = "n1",
                                type      = NotificationType.FRIEND_REQUEST,
                                actorId   = "u1",
                                actorName = "Alice Smith",
                                payload   = """{"friendship_id":"f1"}""",
                                isRead    = false,
                                createdAt = "2026-03-09T12:00:00Z",
                            ),
                            AppNotification(
                                id        = "n2",
                                type      = NotificationType.FRIEND_ACCEPTED,
                                actorId   = "u2",
                                actorName = "Bob Jones",
                                payload   = """{"friendship_id":"f2"}""",
                                isRead    = false,
                                createdAt = "2026-03-08T10:30:00Z",
                            ),
                            AppNotification(
                                id        = "n3",
                                type      = NotificationType.FRIEND_REQUEST,
                                actorId   = "u3",
                                actorName = "Charlie",
                                payload   = """{"friendship_id":"f3"}""",
                                isRead    = true,
                                createdAt = "2026-03-07T08:00:00Z",
                            ),
                        ),
                    ),
                    unreadCount = 2,
                ),
                onMarkRead           = {},
                onMarkAllRead        = {},
                onRefresh            = {},
            )
        }
    }
}

@Preview
@Composable
private fun NotificationCenterEmptyPreview() {
    MaterialTheme {
        Surface {
            NotificationCenterContent(
                uiState   = NotificationUiState(listState = NotificationListState.Empty),
                onMarkRead    = {},
                onMarkAllRead = {},
                onRefresh     = {},
            )
        }
    }
}

@Preview
@Composable
private fun NotificationBannerPreview() {
    MaterialTheme {
        Surface {
            NotificationCenterContent(
                uiState = NotificationUiState(
                    listState = NotificationListState.Empty,
                    newNotificationBanner = AppNotification(
                        id        = "n1",
                        type      = NotificationType.FRIEND_REQUEST,
                        actorId   = "u1",
                        actorName = "Alice Smith",
                        payload   = """{"friendship_id":"f1"}""",
                        isRead    = false,
                        createdAt = "2026-03-09T12:00:00Z",
                    ),
                ),
                onMarkRead    = {},
                onMarkAllRead = {},
                onRefresh     = {},
            )
        }
    }
}
