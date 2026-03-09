package com.flomks.pushup.friends

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
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pushup.domain.model.FriendshipStatus
import com.pushup.domain.model.UserSearchResult

// ---------------------------------------------------------------------------
// Screen entry point
// ---------------------------------------------------------------------------

/**
 * Full user-search screen.
 *
 * Observes [viewModel] state and delegates all events back to it.
 */
@Composable
fun UserSearchScreen(
    viewModel: UserSearchViewModel,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()

    UserSearchContent(
        uiState = uiState,
        onQueryChanged = viewModel::onQueryChanged,
        onClearQuery = viewModel::onClearQuery,
        onSendFriendRequest = viewModel::onSendFriendRequest,
        modifier = modifier,
    )
}

// ---------------------------------------------------------------------------
// Stateless content (testable / previewable)
// ---------------------------------------------------------------------------

@Composable
internal fun UserSearchContent(
    uiState: UserSearchUiState,
    onQueryChanged: (String) -> Unit,
    onClearQuery: () -> Unit,
    onSendFriendRequest: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
    ) {
        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Find Friends",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
        )

        Spacer(modifier = Modifier.height(12.dp))

        UserSearchField(
            query = uiState.query,
            onQueryChanged = onQueryChanged,
            onClearQuery = onClearQuery,
        )

        Spacer(modifier = Modifier.height(16.dp))

        when (val state = uiState.searchState) {
            is SearchState.Idle    -> SearchIdleState()
            is SearchState.Loading -> SearchLoadingState()
            is SearchState.Empty   -> SearchEmptyState(query = uiState.query)
            is SearchState.Error   -> SearchErrorState(message = state.message)
            is SearchState.Success -> SearchResultsList(
                results = state.results,
                sendRequestIds = uiState.sendRequestIds,
                onSendFriendRequest = onSendFriendRequest,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Search field
// ---------------------------------------------------------------------------

@Composable
private fun UserSearchField(
    query: String,
    onQueryChanged: (String) -> Unit,
    onClearQuery: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val keyboardController = LocalSoftwareKeyboardController.current

    OutlinedTextField(
        value = query,
        onValueChange = onQueryChanged,
        modifier = modifier.fillMaxWidth(),
        placeholder = { Text("Search by username or name") },
        leadingIcon = {
            Icon(
                imageVector = Icons.Default.Search,
                contentDescription = "Search",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        trailingIcon = {
            if (query.isNotEmpty()) {
                IconButton(onClick = {
                    onClearQuery()
                    keyboardController?.hide()
                }) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Clear search",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        singleLine = true,
        shape = RoundedCornerShape(12.dp),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(
            onSearch = { keyboardController?.hide() },
        ),
    )
}

// ---------------------------------------------------------------------------
// Empty / loading / error states
// ---------------------------------------------------------------------------

@Composable
private fun SearchIdleState() {
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
                text = "Search for users",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Type at least 2 characters to start",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            )
        }
    }
}

@Composable
private fun SearchLoadingState() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator()
    }
}

@Composable
private fun SearchEmptyState(query: String) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.Search,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "No users found",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "No results for \"$query\"",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            )
        }
    }
}

@Composable
private fun SearchErrorState(message: String) {
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
        }
    }
}

// ---------------------------------------------------------------------------
// Results list
// ---------------------------------------------------------------------------

@Composable
private fun SearchResultsList(
    results: List<UserSearchResult>,
    sendRequestIds: Set<String>,
    onSendFriendRequest: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(modifier = modifier) {
        items(
            items = results,
            key = { it.id },
        ) { result ->
            UserSearchResultItem(
                result = result,
                isSendingRequest = sendRequestIds.contains(result.id),
                onSendFriendRequest = { onSendFriendRequest(result.id) },
            )
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Single result row
// ---------------------------------------------------------------------------

@Composable
private fun UserSearchResultItem(
    result: UserSearchResult,
    isSendingRequest: Boolean,
    onSendFriendRequest: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Avatar
        UserAvatar(
            displayName = result.displayName ?: result.username ?: "?",
        )

        Spacer(modifier = Modifier.width(12.dp))

        // Name + username
        Column(modifier = Modifier.weight(1f)) {
            val primaryName = result.displayName ?: result.username ?: "Unknown"
            Text(
                text = primaryName,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (result.username != null && result.displayName != null) {
                Text(
                    text = "@${result.username}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        Spacer(modifier = Modifier.width(8.dp))

        // Action area: badge or button
        when (result.friendshipStatus) {
            FriendshipStatus.FRIEND  -> FriendBadge()
            FriendshipStatus.PENDING -> PendingBadge()
            FriendshipStatus.NONE    -> SendRequestButton(
                isLoading = isSendingRequest,
                onClick = onSendFriendRequest,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Status badges
// ---------------------------------------------------------------------------

@Composable
private fun FriendBadge() {
    Surface(
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.secondaryContainer,
    ) {
        Text(
            text = "Friends",
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSecondaryContainer,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun PendingBadge() {
    Surface(
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.tertiaryContainer,
    ) {
        Text(
            text = "Pending",
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onTertiaryContainer,
            fontWeight = FontWeight.Medium,
        )
    }
}

// ---------------------------------------------------------------------------
// Send request button
// ---------------------------------------------------------------------------

@Composable
private fun SendRequestButton(
    isLoading: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Button(
        onClick = onClick,
        enabled = !isLoading,
        modifier = modifier.height(36.dp),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
        shape = RoundedCornerShape(20.dp),
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onPrimary,
            )
        } else {
            Text(
                text = "Add Friend",
                style = MaterialTheme.typography.labelMedium,
                fontSize = 13.sp,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Preview
// ---------------------------------------------------------------------------

@Preview
@Composable
private fun UserSearchScreenPreview() {
    MaterialTheme {
        UserSearchContent(
            uiState = UserSearchUiState(
                query = "john",
                searchState = SearchState.Success(
                    results = listOf(
                        UserSearchResult(
                            id = "1",
                            username = "john_doe",
                            displayName = "John Doe",
                            avatarUrl = null,
                            friendshipStatus = FriendshipStatus.NONE,
                        ),
                        UserSearchResult(
                            id = "2",
                            username = "johnny",
                            displayName = "Johnny B",
                            avatarUrl = null,
                            friendshipStatus = FriendshipStatus.PENDING,
                        ),
                        UserSearchResult(
                            id = "3",
                            username = "john_smith",
                            displayName = "John Smith",
                            avatarUrl = null,
                            friendshipStatus = FriendshipStatus.FRIEND,
                        ),
                    ),
                ),
            ),
            onQueryChanged = {},
            onClearQuery = {},
            onSendFriendRequest = {},
        )
    }
}
