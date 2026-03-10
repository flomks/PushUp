package com.flomks.pushup.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pushup.domain.model.TotalStats
import com.pushup.domain.model.User
import com.pushup.domain.model.UserLevel
import com.pushup.domain.usecase.GetOrCreateLocalUserUseCase
import com.pushup.domain.usecase.GetTotalStatsUseCase
import com.pushup.domain.usecase.GetUserLevelUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

/**
 * Represents the overall loading / content / error state of the profile screen.
 */
sealed interface ProfileState {
    /** Initial load is in progress. */
    data object Loading : ProfileState

    /** Data loaded successfully. */
    data class Success(
        val user: User,
        val userLevel: UserLevel,
        val totalStats: TotalStats?,
    ) : ProfileState

    /** Load failed with an error message. */
    data class Error(val message: String) : ProfileState
}

/**
 * UI state for the profile screen.
 *
 * @property profileState Current loading / content / error state.
 */
data class ProfileUiState(
    val profileState: ProfileState = ProfileState.Loading,
)

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * ViewModel for the profile screen.
 *
 * Loads the current user, their XP / level, and lifetime stats on creation.
 *
 * @property getUserUseCase Use-case for retrieving the current local user.
 * @property getUserLevelUseCase Use-case for retrieving the user's XP / level.
 * @property getTotalStatsUseCase Use-case for retrieving lifetime workout stats.
 */
class ProfileViewModel(
    private val getUserUseCase: GetOrCreateLocalUserUseCase,
    private val getUserLevelUseCase: GetUserLevelUseCase,
    private val getTotalStatsUseCase: GetTotalStatsUseCase,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ProfileUiState())
    val uiState: StateFlow<ProfileUiState> = _uiState.asStateFlow()

    init {
        loadProfile()
    }

    // -------------------------------------------------------------------------
    // Public events
    // -------------------------------------------------------------------------

    /**
     * Reloads all profile data.
     */
    fun onRefresh() {
        loadProfile()
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    private fun loadProfile() {
        viewModelScope.launch {
            _uiState.update { it.copy(profileState = ProfileState.Loading) }
            try {
                val user = getUserUseCase()
                val userLevel = getUserLevelUseCase(user.id)
                val totalStats = getTotalStatsUseCase(user.id)

                _uiState.update {
                    it.copy(
                        profileState = ProfileState.Success(
                            user = user,
                            userLevel = userLevel,
                            totalStats = totalStats,
                        ),
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        profileState = ProfileState.Error(
                            message = e.message ?: "Failed to load profile.",
                        ),
                    )
                }
            }
        }
    }
}
