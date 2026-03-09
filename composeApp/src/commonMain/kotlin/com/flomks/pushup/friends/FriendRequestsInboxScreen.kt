package com.flomks.pushup.friends

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.pushup.domain.model.FriendRequest

// ---------------------------------------------------------------------------
// Screen entry point
// ---------------------------------------------------------------------------

/**
 * Full friend-requests inbox screen.
 *
 * Observes [viewModel] state and delegates all events back to it.
 */
@Composable
fun FriendRequestsInboxScreen(
    viewModel: FriendRequestsViewModel,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()

    FriendRequestsInboxContent(
        uiState = uiState,
        onAccept = viewModel::onAccept,
        onDecline = viewModel::onDecline,
        onRefresh = viewModel::onRefresh,
        onDismissActionError = viewModel::onDismissActionError,
        modifier = modifier,
    )
}

// ---------------------------------------------------------------------------
// Stateless content (testable / previewable)
// ---------------------------------------------------------------------------

@Composable
internal fun FriendRequestsInboxContent(
    uiState: FriendRequestsUiState,
    onAccept: (String) -> Unit,
    onDecline: (String) -> Unit,
    onRefresh: () -> Unit,
    onDismissActionError: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
    ) {
        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Friend Requests",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
        )

        // Transient error banner for failed accept/decline actions.
        if (uiState.actionError != null) {
            Spacer(modifier = Modifier.height(8.dp))
            ActionErrorBanner(
                message = uiState.actionError,
                onDismiss = onDismissActionError,
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        when (val state = uiState.inboxState) {
            is InboxState.Loading -> InboxLoadingState()
            is InboxState.Empty   -> InboxEmptyState()
            is InboxState.Error   -> InboxErrorState(message = state.message, onRetry = onRefresh)
            is InboxState.Success -> FriendRequestsList(
                requests          = state.requests,
                actionInFlightIds = uiState.actionInFlightIds,
                onAccept          = onAccept,
                onDecline         = onDecline,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Action error banner
// ---------------------------------------------------------------------------

/**
 * Dismissible error banner shown when an accept/decline action fails.
 *
 * Displayed between the title and the list so it does not obscure content.
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
private fun InboxLoadingState() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator()
    }
}

@Composable
private fun InboxEmptyState() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.Person,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "No pending requests",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "You have no incoming friend requests",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            )
        }
    }
}

@Composable
private fun InboxErrorState(
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
// Requests list
// ---------------------------------------------------------------------------

@Composable
private fun FriendRequestsList(
    requests: List<FriendRequest>,
    actionInFlightIds: Set<String>,
    onAccept: (String) -> Unit,
    onDecline: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(modifier = modifier) {
        items(
            items = requests,
            key = { it.friendshipId },
        ) { request ->
            FriendRequestItem(
                request = request,
                isActionInFlight = actionInFlightIds.contains(request.friendshipId),
                onAccept = { onAccept(request.friendshipId) },
                onDecline = { onDecline(request.friendshipId) },
            )
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Single request row
// ---------------------------------------------------------------------------

@Composable
private fun FriendRequestItem(
    request: FriendRequest,
    isActionInFlight: Boolean,
    onAccept: () -> Unit,
    onDecline: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Avatar (shared composable)
        UserAvatar(
            displayName = request.displayName ?: request.username ?: "?",
        )

        Spacer(modifier = Modifier.width(12.dp))

        // Name + username
        Column(modifier = Modifier.weight(1f)) {
            val primaryName = request.displayName ?: request.username ?: "Unknown"
            Text(
                text = primaryName,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (request.username != null && request.displayName != null) {
                Text(
                    text = "@${request.username}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        Spacer(modifier = Modifier.width(8.dp))

        // Accept / Decline buttons (or spinner while in flight)
        if (isActionInFlight) {
            CircularProgressIndicator(
                modifier = Modifier.size(24.dp),
                strokeWidth = 2.dp,
            )
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                // Decline button
                OutlinedButton(
                    onClick = onDecline,
                    modifier = Modifier.height(36.dp),
                    contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                    shape = RoundedCornerShape(20.dp),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = MaterialTheme.colorScheme.error,
                    ),
                ) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Decline",
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "Decline",
                        style = MaterialTheme.typography.labelMedium,
                    )
                }

                // Accept button
                Button(
                    onClick = onAccept,
                    modifier = Modifier.height(36.dp),
                    contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                    shape = RoundedCornerShape(20.dp),
                ) {
                    Icon(
                        imageVector = Icons.Default.Check,
                        contentDescription = "Accept",
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "Accept",
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Preview
// ---------------------------------------------------------------------------

@Preview
@Composable
private fun FriendRequestsInboxScreenPreview() {
    MaterialTheme {
        FriendRequestsInboxContent(
            uiState = FriendRequestsUiState(
                inboxState = InboxState.Success(
                    requests = listOf(
                        FriendRequest(
                            friendshipId = "f1",
                            requesterId  = "u1",
                            username     = "alice",
                            displayName  = "Alice Smith",
                            avatarUrl    = null,
                            createdAt    = "2024-01-01T12:00:00Z",
                        ),
                        FriendRequest(
                            friendshipId = "f2",
                            requesterId  = "u2",
                            username     = "bob_jones",
                            displayName  = "Bob Jones",
                            avatarUrl    = null,
                            createdAt    = "2024-01-02T08:30:00Z",
                        ),
                        FriendRequest(
                            friendshipId = "f3",
                            requesterId  = "u3",
                            username     = "charlie",
                            displayName  = null,
                            avatarUrl    = null,
                            createdAt    = "2024-01-03T15:45:00Z",
                        ),
                    ),
                ),
                actionInFlightIds = setOf("f2"),
            ),
            onAccept  = {},
            onDecline = {},
            onRefresh = {},
        )
    }
}

@Preview
@Composable
private fun FriendRequestsInboxEmptyPreview() {
    MaterialTheme {
        FriendRequestsInboxContent(
            uiState   = FriendRequestsUiState(inboxState = InboxState.Empty),
            onAccept  = {},
            onDecline = {},
            onRefresh = {},
        )
    }
}
