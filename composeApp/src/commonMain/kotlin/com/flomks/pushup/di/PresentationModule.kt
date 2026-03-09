package com.flomks.pushup.di

import com.flomks.pushup.friends.UserSearchViewModel
import com.pushup.domain.repository.FriendshipRepository
import org.koin.core.module.dsl.viewModel
import org.koin.dsl.module

/**
 * Koin module for all Compose-layer ViewModels.
 *
 * ViewModels are registered with [viewModel] so that Koin creates a new
 * instance per Compose navigation destination (or per [koinViewModel] call).
 */
val presentationModule = module {
    viewModel {
        UserSearchViewModel(repository = get<FriendshipRepository>())
    }
}
