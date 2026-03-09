package com.flomks.pushup

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.flomks.pushup.friends.FriendRequestsInboxScreen
import com.flomks.pushup.friends.FriendRequestsViewModel
import com.flomks.pushup.friends.InboxState
import com.flomks.pushup.friends.UserSearchScreen
import com.flomks.pushup.friends.UserSearchViewModel
import org.koin.compose.viewmodel.koinViewModel

@Composable
@Preview
fun App() {
    MaterialTheme {
        Surface(
            modifier = Modifier
                .fillMaxSize()
                .safeContentPadding(),
            color = MaterialTheme.colorScheme.background,
        ) {
            FriendsSection()
        }
    }
}

/**
 * Friends section of the app.
 *
 * Shows two tabs:
 * - "Find Friends" -- user search with send-request support.
 * - "Requests"     -- incoming pending friend requests with accept/decline.
 *
 * The "Requests" tab shows a badge with the count of pending requests.
 */
@Composable
fun FriendsSection(
    searchViewModel: UserSearchViewModel = koinViewModel(),
    requestsViewModel: FriendRequestsViewModel = koinViewModel(),
) {
    var selectedTab by remember { mutableIntStateOf(0) }

    // Observe the requests state to compute the badge count.
    val requestsUiState by requestsViewModel.uiState.collectAsState()
    val pendingCount = (requestsUiState.inboxState as? InboxState.Success)
        ?.requests
        ?.size
        ?: 0

    Column(modifier = Modifier.fillMaxSize()) {
        FriendsTabs(
            selectedTab  = selectedTab,
            pendingCount = pendingCount,
            onTabSelected = { selectedTab = it },
        )

        when (selectedTab) {
            0 -> UserSearchScreen(viewModel = searchViewModel)
            1 -> FriendRequestsInboxScreen(viewModel = requestsViewModel)
        }
    }
}

// ---------------------------------------------------------------------------
// Tab bar
// ---------------------------------------------------------------------------

/**
 * Tab row for the friends section.
 *
 * @param selectedTab   Index of the currently selected tab (0 = Find, 1 = Requests).
 * @param pendingCount  Number of pending incoming requests; shown as a badge on tab 1.
 * @param onTabSelected Callback invoked when the user taps a tab.
 */
@Composable
private fun FriendsTabs(
    selectedTab: Int,
    pendingCount: Int,
    onTabSelected: (Int) -> Unit,
) {
    TabRow(selectedTabIndex = selectedTab) {
        // Tab 0: Find Friends
        Tab(
            selected = selectedTab == 0,
            onClick  = { onTabSelected(0) },
            text     = { Text("Find Friends") },
            icon     = {
                Icon(
                    imageVector = Icons.Default.Search,
                    contentDescription = "Find Friends",
                )
            },
        )

        // Tab 1: Requests (with badge)
        Tab(
            selected = selectedTab == 1,
            onClick  = { onTabSelected(1) },
            text     = { Text("Requests") },
            icon     = {
                BadgedBox(
                    badge = {
                        if (pendingCount > 0) {
                            Badge {
                                Text(
                                    text = if (pendingCount > 99) "99+" else pendingCount.toString(),
                                )
                            }
                        }
                    },
                ) {
                    Icon(
                        imageVector = Icons.Default.MailOutline,
                        contentDescription = if (pendingCount > 0) {
                            "$pendingCount pending friend requests"
                        } else {
                            "Friend Requests"
                        },
                    )
                }
            },
        )
    }
}
