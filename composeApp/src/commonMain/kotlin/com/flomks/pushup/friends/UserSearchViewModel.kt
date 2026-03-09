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
 * - Cancellation of in-flight searches when a new query arrives.
 * - Optimistic UI updates when a friend request is sent.
 * - Error state management with user-visible feedback.
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

    /** Tracks the currently running search so it can be cancelled on new input. */
    private var activeSearchJob: Job? = null

    init {
        // Observe query changes, debounce, and trigger search.
        // The filter is removed intentionally -- we handle short/empty queries
        // inside performSearch so that clearing the field properly resets state.
        _queryFlow
            .debounce(DEBOUNCE_MS)
            .distinctUntilChanged()
            .onEach { query -> handleDebouncedQuery(query) }
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
        _queryFlow.value = query

        // Immediately reset to Idle when query is too short so the user
        // does not see stale results while typing a new query.
        if (query.length < MIN_QUERY_LENGTH) {
            activeSearchJob?.cancel()
            _uiState.update { it.copy(searchState = SearchState.Idle) }
        }
    }

    /**
     * Clears the search field and resets the result list.
     */
    fun onClearQuery() {
        activeSearchJob?.cancel()
        _uiState.update { UserSearchUiState() }
        _queryFlow.value = ""
    }

    /**
     * Sends a friend request to the user identified by [userId].
     *
     * Marks the user as "pending" in the result list on success.
     * On conflict (already pending/friends), still updates the badge.
     * On other errors, removes the in-flight indicator and surfaces the error.
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
                updateResultStatus(userId, FriendshipStatus.PENDING)
            } catch (e: ApiException.Conflict) {
                // Already friends or request already pending -- update badge anyway
                updateResultStatus(userId, FriendshipStatus.PENDING)
            } catch (_: Exception) {
                // Remove in-flight indicator; the button reappears so the user can retry
                _uiState.update { state ->
                    state.copy(sendRequestIds = state.sendRequestIds - userId)
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /**
     * Handles a debounced query value. Resets to Idle for short queries,
     * otherwise triggers a search.
     */
    private fun handleDebouncedQuery(query: String) {
        if (query.length < MIN_QUERY_LENGTH) {
            activeSearchJob?.cancel()
            _uiState.update { it.copy(searchState = SearchState.Idle) }
            return
        }
        performSearch(query)
    }

    /**
     * Executes a search API call. Cancels any previously running search first
     * to avoid stale results overwriting newer ones.
     */
    private fun performSearch(query: String) {
        activeSearchJob?.cancel()
        activeSearchJob = viewModelScope.launch {
            _uiState.update { it.copy(searchState = SearchState.Loading) }
            try {
                val sanitized = query.trim()
                val results = repository.searchUsers(sanitized)
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

    /**
     * Updates the friendship status of a single user in the current result list
     * and removes the user from the in-flight set.
     *
     * Extracted to eliminate duplication between the success and conflict paths
     * of [onSendFriendRequest].
     */
    private fun updateResultStatus(userId: String, newStatus: FriendshipStatus) {
        _uiState.update { state ->
            val updatedResults = (state.searchState as? SearchState.Success)
                ?.results
                ?.map { result ->
                    if (result.id == userId) {
                        result.copy(friendshipStatus = newStatus)
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
    }

    companion object {
        /** Debounce delay in milliseconds before triggering a search. */
        const val DEBOUNCE_MS = 300L

        /** Minimum query length before a search is triggered. */
        const val MIN_QUERY_LENGTH = 2
    }
}
