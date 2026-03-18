package com.flomks.pushup.di

import com.flomks.pushup.friends.FriendRequestsViewModel
import com.flomks.pushup.friends.FriendsListViewModel
import com.flomks.pushup.friends.FriendStatsViewModel
import com.flomks.pushup.friends.UserSearchViewModel
import com.flomks.pushup.history.HistoryViewModel
import com.flomks.pushup.profile.ProfileViewModel
import com.pushup.domain.repository.FriendshipRepository
import com.pushup.domain.repository.JoggingSessionRepository
import com.pushup.domain.repository.RoutePointRepository
import com.pushup.domain.repository.WorkoutSessionRepository
import com.pushup.domain.usecase.GetOrCreateLocalUserUseCase
import com.pushup.domain.usecase.GetTotalStatsUseCase
import com.pushup.domain.usecase.GetUserLevelUseCase
import org.koin.core.module.dsl.viewModel
import org.koin.dsl.module

/**
 * Koin module for all Compose-layer ViewModels.
 *
 * ViewModels are registered with [viewModel] so that Koin creates a new
 * instance per Compose navigation destination (or per [koinViewModel] call).
 *
 * [FriendStatsViewModel] accepts runtime parameters (friendId, friendName) and
 * is registered with a parameterised factory so callers can pass them via
 * `koinViewModel(key = friendId) { parametersOf(friendId, friendName) }`.
 *
 * Parameters are resolved by index (not by type) because both are [String].
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
            repository = get<FriendshipRepository>(),
            friendId   = params[0],
            friendName = params[1],
        )
    }

    viewModel {
        ProfileViewModel(
            getUserUseCase = get<GetOrCreateLocalUserUseCase>(),
            getUserLevelUseCase = get<GetUserLevelUseCase>(),
            getTotalStatsUseCase = get<GetTotalStatsUseCase>(),
        )
    }

    viewModel {
        HistoryViewModel(
            getUserUseCase = get<GetOrCreateLocalUserUseCase>(),
            workoutSessionRepository = get<WorkoutSessionRepository>(),
            joggingSessionRepository = get<JoggingSessionRepository>(),
            routePointRepository = get<RoutePointRepository>(),
        )
    }
}
