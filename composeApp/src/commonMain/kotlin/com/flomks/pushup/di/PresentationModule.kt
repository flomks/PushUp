package com.flomks.pushup.di

import com.flomks.pushup.friends.FriendRequestsViewModel
import com.flomks.pushup.friends.FriendsListViewModel
import com.flomks.pushup.friends.FriendStatsViewModel
import com.flomks.pushup.friends.UserSearchViewModel
import com.pushup.domain.repository.FriendshipRepository
import org.koin.core.module.dsl.viewModel
import org.koin.core.module.dsl.viewModelOf
import org.koin.dsl.module

/**
 * Koin module for all Compose-layer ViewModels.
 *
 * ViewModels are registered with [viewModel] so that Koin creates a new
 * instance per Compose navigation destination (or per [koinViewModel] call).
 *
 * [FriendStatsViewModel] accepts runtime parameters (friendId, friendName) and
 * is registered with a parameterised factory so callers can pass them via
 * `koinViewModel { parametersOf(friendId, friendName) }`.
 */
val presentationModule = module {
    viewModel {
        UserSearchViewModel(repository = get<FriendshipRepository>())
    }

    viewModel {
        FriendRequestsViewModel(repository = get<FriendshipRepository>())
    }

    viewModel {
        FriendsListViewModel(repository = get<FriendshipRepository>())
    }

    viewModel { params ->
        FriendStatsViewModel(
            repository  = get<FriendshipRepository>(),
            friendId    = params.get(),
            friendName  = params.get(),
        )
    }
}
