package com.flomks.pushup.friends

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pushup.data.api.ApiException
import com.pushup.domain.model.FriendRequest
import com.pushup.domain.repository.FriendshipRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

/**
 * Represents the state of the friend-requests inbox screen.
 *
 * @property inboxState        Current loading / content / error state.
 * @property actionInFlightIds Set of friendship IDs for which an accept/decline
 *                             call is currently in flight.
 */
data class FriendRequestsUiState(
    val inboxState: InboxState = InboxState.Loading,
    val actionInFlightIds: Set<String> = emptySet(),
)

/**
 * Represents the possible states of the inbox list.
 */
sealed interface InboxState {
    /** Initial load is in progress. */
    data object Loading : InboxState

    /** Loaded successfully with at least one request. */
    data class Success(val requests: List<FriendRequest>) : InboxState

    /** Loaded successfully but there are no pending requests. */
    data object Empty : InboxState

    /** Load failed with an error message. */
    data class Error(val message: String) : InboxState
}

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * ViewModel for the friend-requests inbox screen.
 *
 * Handles:
 * - Loading the list of incoming pending friend requests on creation.
 * - Accepting or declining individual requests with optimistic removal.
 * - Error state management with user-visible feedback.
 *
 * @property repository The [FriendshipRepository] used for API calls.
 */
class FriendRequestsViewModel(
    private val repository: FriendshipRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(FriendRequestsUiState())
    val uiState: StateFlow<FriendRequestsUiState> = _uiState.asStateFlow()

    init {
        loadRequests()
    }

    // -------------------------------------------------------------------------
    // Public events
    // -------------------------------------------------------------------------

    /**
     * Reloads the inbox from the server.
     *
     * Useful for pull-to-refresh or retry after an error.
     */
    fun onRefresh() {
        loadRequests()
    }

    /**
     * Accepts the friend request identified by [friendshipId].
     *
     * Optimistically removes the request from the list on success.
     * On error, removes the in-flight indicator so the user can retry.
     */
    fun onAccept(friendshipId: String) {
        respondToRequest(friendshipId, accept = true)
    }

    /**
     * Declines the friend request identified by [friendshipId].
     *
     * Optimistically removes the request from the list on success.
     * On error, removes the in-flight indicator so the user can retry.
     */
    fun onDecline(friendshipId: String) {
        respondToRequest(friendshipId, accept = false)
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /**
     * Fetches the incoming friend requests and updates [_uiState].
     */
    private fun loadRequests() {
        viewModelScope.launch {
            _uiState.update { it.copy(inboxState = InboxState.Loading) }
            try {
                val requests = repository.getIncomingFriendRequests()
                _uiState.update {
                    it.copy(
                        inboxState = if (requests.isEmpty()) {
                            InboxState.Empty
                        } else {
                            InboxState.Success(requests)
                        },
                    )
                }
            } catch (e: ApiException.Unauthorized) {
                _uiState.update {
                    it.copy(inboxState = InboxState.Error("Session expired. Please log in again."))
                }
            } catch (e: ApiException) {
                _uiState.update {
                    it.copy(inboxState = InboxState.Error("Failed to load requests. Please try again."))
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(inboxState = InboxState.Error("An unexpected error occurred."))
                }
            }
        }
    }

    /**
     * Sends an accept or decline response for the given [friendshipId].
     *
     * On success, removes the request from the current list optimistically.
     * On failure, removes the in-flight indicator so the button reappears.
     */
    private fun respondToRequest(friendshipId: String, accept: Boolean) {
        if (_uiState.value.actionInFlightIds.contains(friendshipId)) return

        viewModelScope.launch {
            // Mark as in-flight
            _uiState.update { state ->
                state.copy(actionInFlightIds = state.actionInFlightIds + friendshipId)
            }

            try {
                repository.respondToFriendRequest(friendshipId, accept)
                // Remove the request from the list on success
                removeRequest(friendshipId)
            } catch (_: Exception) {
                // Remove in-flight indicator; buttons reappear so the user can retry
                _uiState.update { state ->
                    state.copy(actionInFlightIds = state.actionInFlightIds - friendshipId)
                }
            }
        }
    }

    /**
     * Removes a request from the current [InboxState.Success] list and
     * transitions to [InboxState.Empty] if the list becomes empty.
     * Also removes the friendship ID from the in-flight set.
     */
    private fun removeRequest(friendshipId: String) {
        _uiState.update { state ->
            val updatedRequests = (state.inboxState as? InboxState.Success)
                ?.requests
                ?.filter { it.friendshipId != friendshipId }

            val newInboxState = when {
                updatedRequests == null  -> state.inboxState
                updatedRequests.isEmpty() -> InboxState.Empty
                else                     -> InboxState.Success(updatedRequests)
            }

            state.copy(
                inboxState        = newInboxState,
                actionInFlightIds = state.actionInFlightIds - friendshipId,
            )
        }
    }
}
