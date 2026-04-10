package com.flomks.sinura.friends

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pushup.data.api.ApiException
import com.pushup.domain.model.Friend
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
 * Represents the state of the friends list screen.
 *
 * @property listState         Current loading / content / error state.
 * @property removeInFlightIds Set of friend user IDs for which a remove call is currently in flight.
 * @property removeError       Transient error message shown when a remove action fails.
 *                             Cleared when [FriendsListViewModel.onDismissRemoveError] is called.
 */
data class FriendsListUiState(
    val listState: FriendsListState = FriendsListState.Loading,
    val removeInFlightIds: Set<String> = emptySet(),
    val removeError: String? = null,
)

/**
 * Represents the possible states of the friends list.
 */
sealed interface FriendsListState {
    /** Initial load is in progress. */
    data object Loading : FriendsListState

    /** Loaded successfully with at least one friend. */
    data class Success(val friends: List<Friend>) : FriendsListState

    /** Loaded successfully but the user has no friends yet. */
    data object Empty : FriendsListState

    /** Load failed with an error message. */
    data class Error(val message: String) : FriendsListState
}

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * ViewModel for the friends list screen.
 *
 * Handles:
 * - Loading the list of accepted friends on creation.
 * - Removing a friend with optimistic removal from the list.
 * - Error state management with user-visible feedback.
 * - Cancellation of in-flight loads when a new load is triggered.
 *
 * @property repository The [FriendshipRepository] used for API calls.
 */
class FriendsListViewModel(
    private val repository: FriendshipRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(FriendsListUiState())
    val uiState: StateFlow<FriendsListUiState> = _uiState.asStateFlow()

    /** Tracks the currently running load so it can be cancelled on refresh. */
    private var activeLoadJob: Job? = null

    init {
        loadFriends()
    }

    // -------------------------------------------------------------------------
    // Public events
    // -------------------------------------------------------------------------

    /**
     * Reloads the friends list from the server.
     *
     * Cancels any in-flight load to prevent stale results from overwriting
     * the new response.
     */
    fun onRefresh() {
        loadFriends()
    }

    /**
     * Removes the friend identified by [friendId] from the list.
     *
     * Optimistically removes the friend from the list on success.
     * On error, surfaces a transient error message and restores the item.
     */
    fun onRemoveFriend(friendId: String) {
        if (_uiState.value.removeInFlightIds.contains(friendId)) return

        viewModelScope.launch {
            // Mark as in-flight and clear any previous remove error.
            _uiState.update { state ->
                state.copy(
                    removeInFlightIds = state.removeInFlightIds + friendId,
                    removeError = null,
                )
            }

            try {
                repository.removeFriend(friendId)
                removeFriendFromList(friendId)
            } catch (e: ApiException.Unauthorized) {
                _uiState.update { state ->
                    state.copy(
                        removeInFlightIds = state.removeInFlightIds - friendId,
                        removeError = "Session expired. Please log in again.",
                    )
                }
            } catch (e: Exception) {
                _uiState.update { state ->
                    state.copy(
                        removeInFlightIds = state.removeInFlightIds - friendId,
                        removeError = "Failed to remove friend. Please try again.",
                    )
                }
            }
        }
    }

    /**
     * Dismisses the transient remove error message.
     */
    fun onDismissRemoveError() {
        _uiState.update { it.copy(removeError = null) }
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /**
     * Fetches the accepted friends list and updates [_uiState].
     *
     * Cancels any previously running load to avoid stale results overwriting
     * newer ones when the user taps refresh rapidly.
     */
    private fun loadFriends() {
        activeLoadJob?.cancel()
        activeLoadJob = viewModelScope.launch {
            _uiState.update { it.copy(listState = FriendsListState.Loading) }
            try {
                val friends = repository.getFriends()
                _uiState.update {
                    it.copy(
                        listState = if (friends.isEmpty()) {
                            FriendsListState.Empty
                        } else {
                            FriendsListState.Success(friends)
                        },
                    )
                }
            } catch (e: ApiException.Unauthorized) {
                _uiState.update {
                    it.copy(listState = FriendsListState.Error("Session expired. Please log in again."))
                }
            } catch (e: ApiException) {
                _uiState.update {
                    it.copy(listState = FriendsListState.Error("Failed to load friends. Please try again."))
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(listState = FriendsListState.Error("An unexpected error occurred."))
                }
            }
        }
    }

    /**
     * Removes a friend from the current [FriendsListState.Success] list and
     * transitions to [FriendsListState.Empty] if the list becomes empty.
     * Also removes the friend ID from the in-flight set.
     */
    private fun removeFriendFromList(friendId: String) {
        _uiState.update { state ->
            val updatedFriends = (state.listState as? FriendsListState.Success)
                ?.friends
                ?.filter { it.id != friendId }

            val newListState = when {
                updatedFriends == null   -> state.listState
                updatedFriends.isEmpty() -> FriendsListState.Empty
                else                     -> FriendsListState.Success(updatedFriends)
            }

            state.copy(
                listState         = newListState,
                removeInFlightIds = state.removeInFlightIds - friendId,
            )
        }
    }
}
