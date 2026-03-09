package com.flomks.pushup.friends

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pushup.data.api.ApiException
import com.pushup.domain.model.FriendActivityStats
import com.pushup.domain.repository.FriendshipRepository
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

/**
 * Represents the state of the friend stats screen.
 *
 * @property friendId      UUID of the friend whose stats are displayed.
 * @property friendName    Display name or username of the friend (for the title).
 * @property selectedPeriod Currently selected stats period.
 * @property statsState    Current loading / content / error state.
 */
data class FriendStatsUiState(
    val friendId: String = "",
    val friendName: String = "",
    val selectedPeriod: StatsPeriod = StatsPeriod.WEEK,
    val statsState: FriendStatsState = FriendStatsState.Loading,
)

/**
 * Supported time periods for the friend stats screen.
 */
enum class StatsPeriod(val apiValue: String, val label: String) {
    DAY("day", "Today"),
    WEEK("week", "This Week"),
    MONTH("month", "This Month"),
}

/**
 * Represents the possible states of the friend stats content.
 */
sealed interface FriendStatsState {
    /** Load is in progress. */
    data object Loading : FriendStatsState

    /** Loaded successfully with at least one session recorded. */
    data class Success(val stats: FriendActivityStats) : FriendStatsState

    /**
     * Loaded successfully but the friend has no recorded sessions for the
     * selected period (pushupCount == 0 and totalSessions == 0).
     */
    data object Empty : FriendStatsState

    /** Load failed with an error message. */
    data class Error(val message: String) : FriendStatsState
}

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * ViewModel for the friend stats screen.
 *
 * Handles:
 * - Loading stats for a specific friend and period on creation.
 * - Switching between day / week / month periods.
 * - Error state management with user-visible feedback.
 *
 * @property repository The [FriendshipRepository] used for API calls.
 * @property friendId   UUID of the friend whose stats to display.
 * @property friendName Display name or username of the friend (shown in the title).
 */
class FriendStatsViewModel(
    private val repository: FriendshipRepository,
    private val friendId: String,
    private val friendName: String,
) : ViewModel() {

    private val _uiState = MutableStateFlow(
        FriendStatsUiState(
            friendId   = friendId,
            friendName = friendName,
        ),
    )
    val uiState: StateFlow<FriendStatsUiState> = _uiState.asStateFlow()

    /** Tracks the currently running load so it can be cancelled on period change. */
    private var activeLoadJob: Job? = null

    init {
        loadStats()
    }

    // -------------------------------------------------------------------------
    // Public events
    // -------------------------------------------------------------------------

    /**
     * Switches to the given [period] and reloads stats.
     */
    fun onPeriodSelected(period: StatsPeriod) {
        if (_uiState.value.selectedPeriod == period) return
        _uiState.update { it.copy(selectedPeriod = period) }
        loadStats()
    }

    /**
     * Reloads stats for the current period.
     */
    fun onRefresh() {
        loadStats()
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /**
     * Fetches stats for the current [FriendStatsUiState.selectedPeriod] and
     * updates [_uiState].
     *
     * Cancels any previously running load to avoid stale results overwriting
     * newer ones when the user switches periods rapidly.
     */
    private fun loadStats() {
        activeLoadJob?.cancel()
        activeLoadJob = viewModelScope.launch {
            _uiState.update { it.copy(statsState = FriendStatsState.Loading) }
            val period = _uiState.value.selectedPeriod.apiValue
            try {
                val stats = repository.getFriendStats(friendId, period)
                val newState = if (stats.totalSessions == 0) {
                    FriendStatsState.Empty
                } else {
                    FriendStatsState.Success(stats)
                }
                _uiState.update { it.copy(statsState = newState) }
            } catch (e: ApiException.Unauthorized) {
                _uiState.update {
                    it.copy(statsState = FriendStatsState.Error("Session expired. Please log in again."))
                }
            } catch (e: ApiException) {
                _uiState.update {
                    it.copy(statsState = FriendStatsState.Error("Failed to load stats. Please try again."))
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(statsState = FriendStatsState.Error("An unexpected error occurred."))
                }
            }
        }
    }
}
