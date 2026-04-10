package com.flomks.sinura.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pushup.domain.model.MonthlyActivitySummary
import com.pushup.domain.model.TotalStats
import com.pushup.domain.model.User
import com.pushup.domain.model.UserLevel
import com.pushup.domain.usecase.GetActivityStreakUseCase
import com.pushup.domain.usecase.GetMonthlyActivityUseCase
import com.pushup.domain.usecase.GetOrCreateLocalUserUseCase
import com.pushup.domain.usecase.GetTotalStatsUseCase
import com.pushup.domain.usecase.GetUserLevelUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

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
        val monthlyActivity: MonthlyActivitySummary? = null,
        val activityStreakCurrent: Int = 0,
        val activityStreakLongest: Int = 0,
    ) : ProfileState

    /** Load failed with an error message. */
    data class Error(val message: String) : ProfileState
}

/**
 * UI state for the profile screen.
 *
 * @property profileState Current loading / content / error state.
 * @property selectedMonth Currently displayed month for the heatmap (1-12).
 * @property selectedYear Currently displayed year for the heatmap.
 */
data class ProfileUiState(
    val profileState: ProfileState = ProfileState.Loading,
    val selectedMonth: Int = Clock.System.now()
        .toLocalDateTime(TimeZone.currentSystemDefault()).monthNumber,
    val selectedYear: Int = Clock.System.now()
        .toLocalDateTime(TimeZone.currentSystemDefault()).year,
)

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * ViewModel for the profile screen.
 *
 * Loads the current user, their XP / level, lifetime stats, unified activity
 * streak, and monthly heatmap data on creation.
 */
class ProfileViewModel(
    private val getUserUseCase: GetOrCreateLocalUserUseCase,
    private val getUserLevelUseCase: GetUserLevelUseCase,
    private val getTotalStatsUseCase: GetTotalStatsUseCase,
    private val getMonthlyActivityUseCase: GetMonthlyActivityUseCase,
    private val getActivityStreakUseCase: GetActivityStreakUseCase,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ProfileUiState())
    val uiState: StateFlow<ProfileUiState> = _uiState.asStateFlow()

    init {
        loadProfile()
    }

    // -------------------------------------------------------------------------
    // Public events
    // -------------------------------------------------------------------------

    /** Reloads all profile data. */
    fun onRefresh() {
        loadProfile()
    }

    /** Navigate to the previous month in the heatmap. */
    fun onPreviousMonth() {
        _uiState.update { state ->
            val newMonth = if (state.selectedMonth == 1) 12 else state.selectedMonth - 1
            val newYear = if (state.selectedMonth == 1) state.selectedYear - 1 else state.selectedYear
            state.copy(selectedMonth = newMonth, selectedYear = newYear)
        }
        loadHeatmap()
    }

    /** Navigate to the next month in the heatmap. */
    fun onNextMonth() {
        _uiState.update { state ->
            val newMonth = if (state.selectedMonth == 12) 1 else state.selectedMonth + 1
            val newYear = if (state.selectedMonth == 12) state.selectedYear + 1 else state.selectedYear
            state.copy(selectedMonth = newMonth, selectedYear = newYear)
        }
        loadHeatmap()
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

                val currentState = _uiState.value
                val monthlyActivity = getMonthlyActivityUseCase(
                    userId = user.id,
                    month = currentState.selectedMonth,
                    year = currentState.selectedYear,
                )
                val (streakCurrent, streakLongest) = getActivityStreakUseCase(user.id)

                _uiState.update {
                    it.copy(
                        profileState = ProfileState.Success(
                            user = user,
                            userLevel = userLevel,
                            totalStats = totalStats,
                            monthlyActivity = monthlyActivity,
                            activityStreakCurrent = streakCurrent,
                            activityStreakLongest = streakLongest,
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

    private fun loadHeatmap() {
        viewModelScope.launch {
            val state = _uiState.value
            val currentProfile = state.profileState as? ProfileState.Success ?: return@launch
            try {
                val monthlyActivity = getMonthlyActivityUseCase(
                    userId = currentProfile.user.id,
                    month = state.selectedMonth,
                    year = state.selectedYear,
                )
                _uiState.update {
                    it.copy(
                        profileState = currentProfile.copy(
                            monthlyActivity = monthlyActivity,
                        ),
                    )
                }
            } catch (_: Exception) {
                // Silently fail for month navigation — the grid just won't update
            }
        }
    }
}
