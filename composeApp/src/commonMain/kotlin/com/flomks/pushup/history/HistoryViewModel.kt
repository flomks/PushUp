package com.flomks.pushup.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.RoutePoint
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.JoggingSessionRepository
import com.pushup.domain.repository.RoutePointRepository
import com.pushup.domain.repository.WorkoutSessionRepository
import com.pushup.domain.usecase.GetOrCreateLocalUserUseCase
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

// ---------------------------------------------------------------------------
// Unified history item
// ---------------------------------------------------------------------------

/**
 * Represents a single item in the unified workout history list.
 *
 * Wraps either a push-up [WorkoutSession] or a [JoggingSession] so that
 * both activity types can be displayed in a single chronological list.
 */
sealed interface HistoryItem {
    val id: String
    val startedAt: Instant
    val endedAt: Instant?
    val earnedTimeCreditSeconds: Long

    /** A completed push-up workout session. */
    data class PushUp(val session: WorkoutSession) : HistoryItem {
        override val id: String get() = session.id
        override val startedAt: Instant get() = session.startedAt
        override val endedAt: Instant? get() = session.endedAt
        override val earnedTimeCreditSeconds: Long get() = session.earnedTimeCreditSeconds
    }

    /** A completed GPS-tracked jogging session. */
    data class Jogging(val session: JoggingSession) : HistoryItem {
        override val id: String get() = session.id
        override val startedAt: Instant get() = session.startedAt
        override val endedAt: Instant? get() = session.endedAt
        override val earnedTimeCreditSeconds: Long get() = session.earnedTimeCreditSeconds
    }
}

// ---------------------------------------------------------------------------
// Grouped section
// ---------------------------------------------------------------------------

/**
 * A group of history items sharing the same calendar day.
 */
data class HistorySection(
    val dateLabel: String,
    val items: List<HistoryItem>,
)

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

sealed interface HistoryState {
    data object Loading : HistoryState
    data class Success(val sections: List<HistorySection>) : HistoryState
    data class Error(val message: String) : HistoryState
}

data class HistoryUiState(
    val historyState: HistoryState = HistoryState.Loading,
)

// ---------------------------------------------------------------------------
// Jogging detail state
// ---------------------------------------------------------------------------

sealed interface JoggingDetailState {
    data object Loading : JoggingDetailState
    data class Success(
        val session: JoggingSession,
        val routePoints: List<RoutePoint>,
    ) : JoggingDetailState
    data class Error(val message: String) : JoggingDetailState
}

data class JoggingDetailUiState(
    val detailState: JoggingDetailState = JoggingDetailState.Loading,
)

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * ViewModel for the unified activity history screen.
 *
 * Loads both push-up workout sessions and jogging sessions, merges them
 * into a single chronological list grouped by day, and exposes them as
 * observable state.
 */
class HistoryViewModel(
    private val getUserUseCase: GetOrCreateLocalUserUseCase,
    private val workoutSessionRepository: WorkoutSessionRepository,
    private val joggingSessionRepository: JoggingSessionRepository,
    private val routePointRepository: RoutePointRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(HistoryUiState())
    val uiState: StateFlow<HistoryUiState> = _uiState.asStateFlow()

    private val _detailState = MutableStateFlow(JoggingDetailUiState())
    val detailState: StateFlow<JoggingDetailUiState> = _detailState.asStateFlow()

    init {
        loadHistory()
    }

    // -------------------------------------------------------------------------
    // Public events
    // -------------------------------------------------------------------------

    fun onRefresh() {
        loadHistory()
    }

    /**
     * Loads the route points for a jogging session to display on the detail map.
     */
    fun loadJoggingDetail(sessionId: String) {
        viewModelScope.launch {
            _detailState.update { it.copy(detailState = JoggingDetailState.Loading) }
            try {
                val session = joggingSessionRepository.getById(sessionId)
                    ?: throw IllegalStateException("Jogging session not found: $sessionId")
                val routePoints = routePointRepository.getBySessionId(sessionId)
                _detailState.update {
                    it.copy(
                        detailState = JoggingDetailState.Success(
                            session = session,
                            routePoints = routePoints,
                        ),
                    )
                }
            } catch (e: Exception) {
                _detailState.update {
                    it.copy(
                        detailState = JoggingDetailState.Error(
                            message = e.message ?: "Failed to load jogging details.",
                        ),
                    )
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    private fun loadHistory() {
        viewModelScope.launch {
            _uiState.update { it.copy(historyState = HistoryState.Loading) }
            try {
                val user = getUserUseCase()

                // Load both session types in parallel
                val workouts = workoutSessionRepository.getAllByUserId(user.id)
                val joggingSessions = joggingSessionRepository.getAllByUserId(user.id)

                // Merge into unified list, only completed sessions
                val items = buildList {
                    workouts
                        .filter { it.endedAt != null }
                        .forEach { add(HistoryItem.PushUp(it)) }
                    joggingSessions
                        .filter { it.endedAt != null }
                        .forEach { add(HistoryItem.Jogging(it)) }
                }

                // Sort by startedAt descending (most recent first)
                val sorted = items.sortedByDescending { it.startedAt }

                // Group by calendar day
                val sections = groupByDay(sorted)

                _uiState.update {
                    it.copy(historyState = HistoryState.Success(sections = sections))
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        historyState = HistoryState.Error(
                            message = e.message ?: "Failed to load history.",
                        ),
                    )
                }
            }
        }
    }

    private fun groupByDay(items: List<HistoryItem>): List<HistorySection> {
        val tz = TimeZone.currentSystemDefault()
        val grouped = items.groupBy { item ->
            val localDate = item.startedAt.toLocalDateTime(tz).date
            localDate
        }

        return grouped.map { (date, dayItems) ->
            val label = "${date.dayOfMonth}. ${date.month.name.lowercase().replaceFirstChar { it.uppercase() }} ${date.year}"
            HistorySection(dateLabel = label, items = dayItems)
        }
    }
}
