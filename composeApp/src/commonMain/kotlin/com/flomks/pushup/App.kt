package com.flomks.pushup

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
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
 * Currently shows the user-search screen. Future tasks will add:
 * - Friend requests (accept / deny)
 * - Friend list
 * - Friend stats
 */
@Composable
fun FriendsSection(
    viewModel: UserSearchViewModel = koinViewModel(),
) {
    UserSearchScreen(viewModel = viewModel)
}
