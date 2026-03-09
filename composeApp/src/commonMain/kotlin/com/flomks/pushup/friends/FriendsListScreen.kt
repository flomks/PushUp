package com.flomks.pushup.friends

import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.pushup.domain.model.Friend

// ---------------------------------------------------------------------------
// Screen entry point
// ---------------------------------------------------------------------------

/**
 * Full friends list screen.
 *
 * Observes [viewModel] state and delegates all events back to it.
 * Tapping a friend row calls [onFriendClick] with the friend's user ID so the
 * caller can navigate to the stats view.
 */
@Composable
fun FriendsListScreen(
    viewModel: FriendsListViewModel,
    onFriendClick: (friendId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()

    FriendsListContent(
        uiState = uiState,
        onFriendClick = onFriendClick,
        onRemoveFriend = viewModel::onRemoveFriend,
        onRefresh = viewModel::onRefresh,
        onDismissRemoveError = viewModel::onDismissRemoveError,
        modifier = modifier,
    )
}

// ---------------------------------------------------------------------------
// Stateless content (testable / previewable)
// ---------------------------------------------------------------------------

@Composable
internal fun FriendsListContent(
    uiState: FriendsListUiState,
    onFriendClick: (friendId: String) -> Unit,
    onRemoveFriend: (friendId: String) -> Unit,
    onRefresh: () -> Unit,
    onDismissRemoveError: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
    ) {
        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Friends",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
        )

        // Transient error banner for failed remove actions.
        if (uiState.removeError != null) {
            Spacer(modifier = Modifier.height(8.dp))
            RemoveErrorBanner(
                message = uiState.removeError,
                onDismiss = onDismissRemoveError,
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        when (val state = uiState.listState) {
            is FriendsListState.Loading -> FriendsLoadingState()
            is FriendsListState.Empty   -> FriendsEmptyState()
            is FriendsListState.Error   -> FriendsErrorState(message = state.message, onRetry = onRefresh)
            is FriendsListState.Success -> FriendsList(
                friends           = state.friends,
                removeInFlightIds = uiState.removeInFlightIds,
                onFriendClick     = onFriendClick,
                onRemoveFriend    = onRemoveFriend,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Error banner
// ---------------------------------------------------------------------------

/**
 * Dismissible error banner shown when a remove action fails.
 */
@Composable
private fun RemoveErrorBanner(
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
private fun FriendsLoadingState() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator()
    }
}

@Composable
private fun FriendsEmptyState() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.Group,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "No friends yet",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Search for users and send friend requests",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            )
        }
    }
}

@Composable
private fun FriendsErrorState(
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
// Friends list
// ---------------------------------------------------------------------------

@Composable
private fun FriendsList(
    friends: List<Friend>,
    removeInFlightIds: Set<String>,
    onFriendClick: (friendId: String) -> Unit,
    onRemoveFriend: (friendId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(modifier = modifier) {
        items(
            items = friends,
            key = { it.id },
        ) { friend ->
            FriendItem(
                friend = friend,
                isRemoveInFlight = removeInFlightIds.contains(friend.id),
                onClick = { onFriendClick(friend.id) },
                onRemove = { onRemoveFriend(friend.id) },
            )
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Single friend row
// ---------------------------------------------------------------------------

/**
 * A single row in the friends list.
 *
 * Tapping the row navigates to the friend's stats view.
 * The remove icon button shows a confirmation dialog before removing.
 */
@Composable
private fun FriendItem(
    friend: Friend,
    isRemoveInFlight: Boolean,
    onClick: () -> Unit,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showConfirmDialog by remember { mutableStateOf(false) }

    if (showConfirmDialog) {
        RemoveFriendConfirmDialog(
            friendName = friend.displayName ?: friend.username ?: "this friend",
            onConfirm = {
                showConfirmDialog = false
                onRemove()
            },
            onDismiss = { showConfirmDialog = false },
        )
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Avatar
        UserAvatar(
            displayName = friend.displayName ?: friend.username ?: "?",
        )

        Spacer(modifier = Modifier.width(12.dp))

        // Name + username
        Column(modifier = Modifier.weight(1f)) {
            val primaryName = friend.displayName ?: friend.username ?: "Unknown"
            Text(
                text = primaryName,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (friend.username != null && friend.displayName != null) {
                Text(
                    text = "@${friend.username}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        Spacer(modifier = Modifier.width(8.dp))

        // Remove button or spinner
        if (isRemoveInFlight) {
            CircularProgressIndicator(
                modifier = Modifier.size(24.dp),
                strokeWidth = 2.dp,
            )
        } else {
            IconButton(onClick = { showConfirmDialog = true }) {
                Icon(
                    imageVector = Icons.Default.Delete,
                    contentDescription = "Remove friend",
                    tint = MaterialTheme.colorScheme.error.copy(alpha = 0.7f),
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Confirmation dialog
// ---------------------------------------------------------------------------

/**
 * Confirmation dialog shown before removing a friend.
 *
 * Prevents accidental removal by requiring an explicit confirmation tap.
 */
@Composable
private fun RemoveFriendConfirmDialog(
    friendName: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(text = "Remove Friend")
        },
        text = {
            Text(text = "Remove $friendName from your friends list?")
        },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(
                    text = "Remove",
                    color = MaterialTheme.colorScheme.error,
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(text = "Cancel")
            }
        },
    )
}

// ---------------------------------------------------------------------------
// Preview
// ---------------------------------------------------------------------------

@Preview
@Composable
private fun FriendsListScreenPreview() {
    MaterialTheme {
        FriendsListContent(
            uiState = FriendsListUiState(
                listState = FriendsListState.Success(
                    friends = listOf(
                        Friend(
                            id          = "u1",
                            username    = "alice",
                            displayName = "Alice Smith",
                            avatarUrl   = null,
                        ),
                        Friend(
                            id          = "u2",
                            username    = "bob_jones",
                            displayName = "Bob Jones",
                            avatarUrl   = null,
                        ),
                        Friend(
                            id          = "u3",
                            username    = "charlie",
                            displayName = null,
                            avatarUrl   = null,
                        ),
                    ),
                ),
                removeInFlightIds = setOf("u2"),
            ),
            onFriendClick = {},
            onRemoveFriend = {},
            onRefresh = {},
        )
    }
}

@Preview
@Composable
private fun FriendsListEmptyPreview() {
    MaterialTheme {
        FriendsListContent(
            uiState = FriendsListUiState(listState = FriendsListState.Empty),
            onFriendClick = {},
            onRemoveFriend = {},
            onRefresh = {},
        )
    }
}
