package com.flomks.sinura.friends

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pushup.data.api.ApiException
import com.pushup.domain.model.FriendRequest
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
 * Represents the state of the friend-requests inbox screen.
 *
 * @property inboxState        Current loading / content / error state.
 * @property actionInFlightIds Set of friendship IDs for which an accept/decline
 *                             call is currently in flight.
 * @property actionError       Transient error message shown when an accept/decline
 *                             action fails. Cleared on the next successful action
 *                             or when [FriendRequestsViewModel.onDismissActionError]
 *                             is called.
 */
data class FriendRequestsUiState(
    val inboxState: InboxState = InboxState.Loading,
    val actionInFlightIds: Set<String> = emptySet(),
    val actionError: String? = null,
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
 * - Cancellation of in-flight loads when a new load is triggered.
 *
 * @property repository The [FriendshipRepository] used for API calls.
 */
class FriendRequestsViewModel(
    private val repository: FriendshipRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(FriendRequestsUiState())
    val uiState: StateFlow<FriendRequestsUiState> = _uiState.asStateFlow()

    /** Tracks the currently running load so it can be cancelled on refresh. */
    private var activeLoadJob: Job? = null

    init {
        loadRequests()
    }

    // -------------------------------------------------------------------------
    // Public events
    // -------------------------------------------------------------------------

    /**
     * Reloads the inbox from the server.
     *
     * Cancels any in-flight load to prevent stale results from overwriting
     * the new response.
     */
    fun onRefresh() {
        loadRequests()
    }

    /**
     * Accepts the friend request identified by [friendshipId].
     *
     * Optimistically removes the request from the list on success.
     * On error, surfaces a transient error message and restores the buttons.
     */
    fun onAccept(friendshipId: String) {
        respondToRequest(friendshipId, accept = true)
    }

    /**
     * Declines the friend request identified by [friendshipId].
     *
     * Optimistically removes the request from the list on success.
     * On error, surfaces a transient error message and restores the buttons.
     */
    fun onDecline(friendshipId: String) {
        respondToRequest(friendshipId, accept = false)
    }

    /**
     * Dismisses the transient action error message.
     */
    fun onDismissActionError() {
        _uiState.update { it.copy(actionError = null) }
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /**
     * Fetches the incoming friend requests and updates [_uiState].
     *
     * Cancels any previously running load to avoid stale results overwriting
     * newer ones when the user taps refresh rapidly.
     */
    private fun loadRequests() {
        activeLoadJob?.cancel()
        activeLoadJob = viewModelScope.launch {
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
     * On success, removes the request from the current list.
     * On failure, removes the in-flight indicator so the buttons reappear
     * and surfaces a transient error message.
     */
    private fun respondToRequest(friendshipId: String, accept: Boolean) {
        if (_uiState.value.actionInFlightIds.contains(friendshipId)) return

        viewModelScope.launch {
            // Mark as in-flight and clear any previous action error.
            _uiState.update { state ->
                state.copy(
                    actionInFlightIds = state.actionInFlightIds + friendshipId,
                    actionError = null,
                )
            }

            try {
                repository.respondToFriendRequest(friendshipId, accept)
                // Remove the request from the list on success
                removeRequest(friendshipId)
            } catch (e: ApiException.Unauthorized) {
                _uiState.update { state ->
                    state.copy(
                        actionInFlightIds = state.actionInFlightIds - friendshipId,
                        actionError = "Session expired. Please log in again.",
                    )
                }
            } catch (e: Exception) {
                val action = if (accept) "accept" else "decline"
                _uiState.update { state ->
                    state.copy(
                        actionInFlightIds = state.actionInFlightIds - friendshipId,
                        actionError = "Failed to $action request. Please try again.",
                    )
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
                updatedRequests == null   -> state.inboxState
                updatedRequests.isEmpty() -> InboxState.Empty
                else                      -> InboxState.Success(updatedRequests)
            }

            state.copy(
                inboxState        = newInboxState,
                actionInFlightIds = state.actionInFlightIds - friendshipId,
            )
        }
    }
}
