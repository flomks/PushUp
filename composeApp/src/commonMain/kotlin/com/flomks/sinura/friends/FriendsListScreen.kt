package com.flomks.sinura.friends

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
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
import com.sinura.domain.model.Friend

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

@Composable
internal fun FriendsListContent(
    uiState: FriendsListUiState,
    onFriendClick: (friendId: String) -> Unit,
    onRemoveFriend: (friendId: String) -> Unit,
    onRefresh: () -> Unit,
    onDismissRemoveError: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val friendCount = (uiState.listState as? FriendsListState.Success)?.friends?.size ?: 0

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Spacer(modifier = Modifier.height(4.dp))
        FriendsHeaderCard(friendCount = friendCount)

        if (uiState.removeError != null) {
            RemoveErrorBanner(
                message = uiState.removeError,
                onDismiss = onDismissRemoveError,
            )
        }

        when (val state = uiState.listState) {
            is FriendsListState.Loading -> FriendsLoadingState()
            is FriendsListState.Empty -> FriendsEmptyState()
            is FriendsListState.Error -> FriendsErrorState(
                message = state.message,
                onRetry = onRefresh,
            )
            is FriendsListState.Success -> FriendsList(
                friends = state.friends,
                removeInFlightIds = uiState.removeInFlightIds,
                onFriendClick = onFriendClick,
                onRemoveFriend = onRemoveFriend,
            )
        }
    }
}

@Composable
private fun FriendsHeaderCard(
    friendCount: Int,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.72f),
        ),
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 20.dp),
        ) {
            Text(
                text = "Friends",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = "Open profiles, compare progress and keep your social area tighter and easier to scan.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.92f),
            )
            Spacer(modifier = Modifier.height(16.dp))
            Surface(
                shape = RoundedCornerShape(20.dp),
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.55f),
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Default.Insights,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Spacer(modifier = Modifier.width(10.dp))
                    Column {
                        Text(
                            text = friendCount.toString(),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            text = if (friendCount == 1) "active friend" else "active friends",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RemoveErrorBanner(
    message: String,
    onDismiss: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.5f),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
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
                color = MaterialTheme.colorScheme.onErrorContainer,
            )
            TextButton(onClick = onDismiss) {
                Text(text = "Dismiss", style = MaterialTheme.typography.labelSmall)
            }
        }
    }
}

@Composable
private fun FriendsLoadingState() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 40.dp),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator()
    }
}

@Composable
private fun FriendsEmptyState() {
    Card(
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f),
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 24.dp),
        ) {
            Icon(
                imageVector = Icons.Default.Group,
                contentDescription = null,
                modifier = Modifier.size(60.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "No friends yet",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = "Search for people you know and start building a circle that actually makes the leaderboard feel alive.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun FriendsErrorState(
    message: String,
    onRetry: () -> Unit,
) {
    Card(
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f),
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = null,
                modifier = Modifier.size(56.dp),
                tint = MaterialTheme.colorScheme.error.copy(alpha = 0.8f),
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.error,
            )
            Spacer(modifier = Modifier.height(12.dp))
            TextButton(onClick = onRetry) {
                Text(text = "Retry")
            }
        }
    }
}

@Composable
private fun FriendsList(
    friends: List<Friend>,
    removeInFlightIds: Set<String>,
    onFriendClick: (friendId: String) -> Unit,
    onRemoveFriend: (friendId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = if (friends.size == 1) "1 connection" else "${friends.size} connections",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        friends.forEach { friend ->
            FriendItem(
                friend = friend,
                isRemoveInFlight = removeInFlightIds.contains(friend.id),
                onClick = { onFriendClick(friend.id) },
                onRemove = { onRemoveFriend(friend.id) },
            )
        }
    }
}

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

    Card(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.32f),
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            UserAvatar(
                displayName = friend.displayName ?: friend.username ?: "?",
            )

            Spacer(modifier = Modifier.width(12.dp))

            Column(modifier = Modifier.weight(1f)) {
                val primaryName = friend.displayName ?: friend.username ?: "Unknown"
                Text(
                    text = primaryName,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (friend.username != null && friend.displayName != null) {
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = "@${friend.username}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
                Surface(
                    shape = RoundedCornerShape(16.dp),
                    color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.75f),
                ) {
                    Text(
                        text = "Open activity profile",
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                }
            }

            Spacer(modifier = Modifier.width(8.dp))

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
                        tint = MaterialTheme.colorScheme.error.copy(alpha = 0.75f),
                    )
                }
            }
        }
    }
}

@Composable
private fun RemoveFriendConfirmDialog(
    friendName: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(text = "Remove Friend") },
        text = { Text(text = "Remove $friendName from your friends list?") },
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

@Preview
@Composable
private fun FriendsListScreenPreview() {
    MaterialTheme {
        FriendsListContent(
            uiState = FriendsListUiState(
                listState = FriendsListState.Success(
                    friends = listOf(
                        Friend(
                            id = "u1",
                            username = "alice",
                            displayName = "Alice Smith",
                            avatarUrl = null,
                        ),
                        Friend(
                            id = "u2",
                            username = "bob_jones",
                            displayName = "Bob Jones",
                            avatarUrl = null,
                        ),
                        Friend(
                            id = "u3",
                            username = "charlie",
                            displayName = null,
                            avatarUrl = null,
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
