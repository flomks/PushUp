package com.flomks.pushup.friends

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pushup.data.api.ApiException
import com.pushup.domain.model.FriendshipStatus
import com.pushup.domain.model.UserSearchResult
import com.pushup.domain.repository.FriendshipRepository
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

/**
 * Represents the state of the user-search screen.
 *
 * @property query          Current text in the search field.
 * @property searchState    Current state of the search results.
 * @property sendRequestIds Set of user IDs for which a send-request call is in flight.
 */
data class UserSearchUiState(
    val query: String = "",
    val searchState: SearchState = SearchState.Idle,
    val sendRequestIds: Set<String> = emptySet(),
)

/**
 * Represents the possible states of the search result list.
 */
sealed interface SearchState {
    /** No search has been performed yet (query is empty or too short). */
    data object Idle : SearchState

    /** A search is currently in progress. */
    data object Loading : SearchState

    /** Search completed successfully. */
    data class Success(val results: List<UserSearchResult>) : SearchState

    /** Search returned no results. */
    data object Empty : SearchState

    /** Search failed with an error. */
    data class Error(val message: String) : SearchState
}

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * ViewModel for the user-search screen.
 *
 * Handles:
 * - Debounced search (300 ms) triggered by query changes.
 * - Optimistic UI updates when a friend request is sent.
 * - Error state management.
 *
 * @property repository The [FriendshipRepository] used for API calls.
 */
@OptIn(FlowPreview::class)
class UserSearchViewModel(
    private val repository: FriendshipRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(UserSearchUiState())
    val uiState: StateFlow<UserSearchUiState> = _uiState.asStateFlow()

    /** Internal flow of raw query strings, debounced before triggering a search. */
    private val _queryFlow = MutableStateFlow("")

    init {
        // Observe query changes, debounce, and trigger search.
        _queryFlow
            .debounce(DEBOUNCE_MS)
            .distinctUntilChanged()
            .filter { it.length >= MIN_QUERY_LENGTH }
            .onEach { query -> performSearch(query) }
            .launchIn(viewModelScope)
    }

    // -------------------------------------------------------------------------
    // Public events
    // -------------------------------------------------------------------------

    /**
     * Called whenever the user types in the search field.
     *
     * Updates the query in the UI state immediately (so the text field stays
     * responsive) and pushes the new value into the debounce pipeline.
     */
    fun onQueryChanged(query: String) {
        _uiState.update { it.copy(query = query) }
        if (query.length < MIN_QUERY_LENGTH) {
            _uiState.update { it.copy(searchState = SearchState.Idle) }
        }
        _queryFlow.value = query
    }

    /**
     * Clears the search field and resets the result list.
     */
    fun onClearQuery() {
        _uiState.update { UserSearchUiState() }
        _queryFlow.value = ""
    }

    /**
     * Sends a friend request to the user identified by [userId].
     *
     * Optimistically marks the user as "pending" in the result list so the UI
     * updates immediately. If the request fails, the original status is restored
     * and an error is surfaced.
     */
    fun onSendFriendRequest(userId: String) {
        if (_uiState.value.sendRequestIds.contains(userId)) return

        viewModelScope.launch {
            // Mark as in-flight
            _uiState.update { state ->
                state.copy(sendRequestIds = state.sendRequestIds + userId)
            }

            try {
                repository.sendFriendRequest(userId)

                // Optimistically update the friendship status in the result list
                _uiState.update { state ->
                    val updatedResults = (state.searchState as? SearchState.Success)
                        ?.results
                        ?.map { result ->
                            if (result.id == userId) {
                                result.copy(friendshipStatus = FriendshipStatus.PENDING)
                            } else {
                                result
                            }
                        }
                    state.copy(
                        sendRequestIds = state.sendRequestIds - userId,
                        searchState = if (updatedResults != null) {
                            SearchState.Success(updatedResults)
                        } else {
                            state.searchState
                        },
                    )
                }
            } catch (e: ApiException.Conflict) {
                // Already friends or request already pending -- update status badge
                _uiState.update { state ->
                    val updatedResults = (state.searchState as? SearchState.Success)
                        ?.results
                        ?.map { result ->
                            if (result.id == userId) {
                                result.copy(friendshipStatus = FriendshipStatus.PENDING)
                            } else {
                                result
                            }
                        }
                    state.copy(
                        sendRequestIds = state.sendRequestIds - userId,
                        searchState = if (updatedResults != null) {
                            SearchState.Success(updatedResults)
                        } else {
                            state.searchState
                        },
                    )
                }
            } catch (e: Exception) {
                _uiState.update { state ->
                    state.copy(sendRequestIds = state.sendRequestIds - userId)
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    private fun performSearch(query: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(searchState = SearchState.Loading) }
            try {
                val results = repository.searchUsers(query)
                _uiState.update {
                    it.copy(
                        searchState = if (results.isEmpty()) {
                            SearchState.Empty
                        } else {
                            SearchState.Success(results)
                        },
                    )
                }
            } catch (e: ApiException.Unauthorized) {
                _uiState.update {
                    it.copy(searchState = SearchState.Error("Session expired. Please log in again."))
                }
            } catch (e: ApiException) {
                _uiState.update {
                    it.copy(searchState = SearchState.Error("Search failed. Please try again."))
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(searchState = SearchState.Error("An unexpected error occurred."))
                }
            }
        }
    }

    companion object {
        /** Debounce delay in milliseconds before triggering a search. */
        const val DEBOUNCE_MS = 300L

        /** Minimum query length before a search is triggered. */
        const val MIN_QUERY_LENGTH = 2
    }
}
