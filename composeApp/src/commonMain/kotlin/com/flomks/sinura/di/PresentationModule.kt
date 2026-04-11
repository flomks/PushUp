package com.flomks.sinura.di

import com.flomks.sinura.friends.FriendRequestsViewModel
import com.flomks.sinura.friends.FriendsListViewModel
import com.flomks.sinura.friends.FriendStatsViewModel
import com.flomks.sinura.friends.UserSearchViewModel
import com.flomks.sinura.history.HistoryViewModel
import com.flomks.sinura.profile.ProfileViewModel
import com.sinura.domain.repository.FriendshipRepository
import com.sinura.domain.repository.JoggingSegmentRepository
import com.sinura.domain.repository.JoggingSessionRepository
import com.sinura.domain.repository.RoutePointRepository
import com.sinura.domain.repository.WorkoutSessionRepository
import com.sinura.domain.usecase.GetActivityStreakUseCase
import com.sinura.domain.usecase.GetMonthlyActivityUseCase
import com.sinura.domain.usecase.GetOrCreateLocalUserUseCase
import com.sinura.domain.usecase.GetTotalStatsUseCase
import com.sinura.domain.usecase.GetUserLevelUseCase
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
            getMonthlyActivityUseCase = get<GetMonthlyActivityUseCase>(),
            getActivityStreakUseCase = get<GetActivityStreakUseCase>(),
        )
    }

    viewModel {
        HistoryViewModel(
            getUserUseCase = get<GetOrCreateLocalUserUseCase>(),
            workoutSessionRepository = get<WorkoutSessionRepository>(),
            joggingSessionRepository = get<JoggingSessionRepository>(),
            joggingSegmentRepository = get<JoggingSegmentRepository>(),
            routePointRepository = get<RoutePointRepository>(),
        )
    }
}
