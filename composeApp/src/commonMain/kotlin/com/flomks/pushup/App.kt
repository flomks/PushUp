package com.flomks.pushup

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material.icons.filled.Person
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.flomks.pushup.friends.FriendRequestsInboxScreen
import com.flomks.pushup.friends.FriendRequestsViewModel
import com.flomks.pushup.friends.FriendsListScreen
import com.flomks.pushup.friends.FriendsListState
import com.flomks.pushup.friends.FriendsListViewModel
import com.flomks.pushup.friends.FriendStatsScreen
import com.flomks.pushup.friends.FriendStatsViewModel
import com.flomks.pushup.friends.InboxState
import com.flomks.pushup.friends.UserSearchScreen
import com.flomks.pushup.friends.UserSearchViewModel
import com.flomks.pushup.profile.ProfileScreen
import com.flomks.pushup.profile.ProfileViewModel
import org.koin.compose.viewmodel.koinViewModel
import org.koin.core.parameter.parametersOf

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
            MainScreen()
        }
    }
}

/**
 * Top-level screen with two main sections:
 * - "Profile" tab: shows the user's level, XP progress, and lifetime stats.
 * - "Social" tab: the existing friends / notifications section.
 */
@Composable
fun MainScreen(
    profileViewModel: ProfileViewModel = koinViewModel(),
) {
    var selectedMainTab by remember { mutableIntStateOf(0) }

    Column(modifier = Modifier.fillMaxSize()) {
        // Top-level tab row
        TabRow(selectedTabIndex = selectedMainTab) {
            Tab(
                selected = selectedMainTab == 0,
                onClick = { selectedMainTab = 0 },
                text = { Text("Profile") },
                icon = {
                    Icon(
                        imageVector = Icons.Default.Person,
                        contentDescription = "Profile",
                    )
                },
            )
            Tab(
                selected = selectedMainTab == 1,
                onClick = { selectedMainTab = 1 },
                text = { Text("Social") },
                icon = {
                    Icon(
                        imageVector = Icons.Default.Group,
                        contentDescription = "Social",
                    )
                },
            )
        }

        when (selectedMainTab) {
            0 -> ProfileScreen(viewModel = profileViewModel)
            1 -> FriendsSection()
        }
    }
}

/**
 * Friends section of the app.
 *
 * Shows three tabs:
 * - "Find Friends"   -- user search with send-request support.
 * - "Requests"       -- incoming pending friend requests with accept/decline.
 * - "Friends"        -- list of accepted friends with stats navigation and remove.
 *
 * The "Requests" tab shows a badge with the count of pending requests.
 * Tapping a friend in the "Friends" tab navigates to their stats screen.
 */
@Composable
fun FriendsSection(
    searchViewModel: UserSearchViewModel = koinViewModel(),
    requestsViewModel: FriendRequestsViewModel = koinViewModel(),
    friendsListViewModel: FriendsListViewModel = koinViewModel(),
) {
    var selectedTab by remember { mutableIntStateOf(0) }

    // Observe the requests state to compute the badge count.
    val requestsUiState by requestsViewModel.uiState.collectAsState()
    val pendingCount = (requestsUiState.inboxState as? InboxState.Success)
        ?.requests
        ?.size
        ?: 0

    // Navigation state: null = show the list, non-null = show stats for that friend.
    // Pair<friendId, friendName>
    var statsTarget by remember { mutableStateOf<Pair<String, String>?>(null) }

    // If a stats target is set, show the stats screen (full-screen overlay within the section).
    // The `key` parameter ensures Koin creates a fresh ViewModel per friend ID,
    // preventing stale data when navigating between different friends.
    val target = statsTarget
    if (target != null) {
        val statsViewModel: FriendStatsViewModel = koinViewModel(
            key = "friend_stats_${target.first}",
            parameters = { parametersOf(target.first, target.second) },
        )
        FriendStatsScreen(
            viewModel = statsViewModel,
            onBack = { statsTarget = null },
        )
        return
    }

    Column(modifier = Modifier.fillMaxSize()) {
        FriendsTabs(
            selectedTab  = selectedTab,
            pendingCount = pendingCount,
            onTabSelected = { selectedTab = it },
        )

        when (selectedTab) {
            0 -> UserSearchScreen(viewModel = searchViewModel)
            1 -> FriendRequestsInboxScreen(viewModel = requestsViewModel)
            2 -> FriendsListScreen(
                viewModel = friendsListViewModel,
                onFriendClick = { friendId ->
                    // Resolve the friend's display name from the current list state.
                    val friendName = (friendsListViewModel.uiState.value.listState as? FriendsListState.Success)
                        ?.friends
                        ?.firstOrNull { it.id == friendId }
                        ?.let { it.displayName ?: it.username ?: "" }
                        ?: ""
                    statsTarget = friendId to friendName
                },
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Tab bar
// ---------------------------------------------------------------------------

/**
 * Tab row for the friends section.
 *
 * @param selectedTab   Index of the currently selected tab
 *                      (0 = Find, 1 = Requests, 2 = Friends).
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

        // Tab 2: Friends list
        Tab(
            selected = selectedTab == 2,
            onClick  = { onTabSelected(2) },
            text     = { Text("Friends") },
            icon     = {
                Icon(
                    imageVector = Icons.Default.Group,
                    contentDescription = "Friends",
                )
            },
        )
    }
}
