package com.sinura.data.api

import com.sinura.data.api.dto.FriendActivityStatsDTO
import com.sinura.data.api.dto.FriendLevelDetailsDTO
import com.sinura.data.api.dto.FriendMonthlyActivityDTO
import com.sinura.data.api.dto.FriendProfileDTO
import com.sinura.data.api.dto.FriendshipResponseDTO
import com.sinura.data.api.dto.FriendsListResponseDTO
import com.sinura.data.api.dto.IncomingFriendRequestsResponseDTO
import com.sinura.data.api.dto.RespondFriendRequestDTO
import com.sinura.data.api.dto.SendFriendRequestDTO
import com.sinura.data.api.dto.UserSearchResponseDTO
import com.sinura.data.api.dto.toDomain
import com.sinura.domain.model.Friend
import com.sinura.domain.model.FriendActivityStats
import com.sinura.domain.model.FriendLevelDetails
import com.sinura.domain.model.FriendMonthlyActivity
import com.sinura.domain.model.Friendship
import com.sinura.domain.model.FriendRequest
import com.sinura.domain.model.UserSearchResult
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.patch
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType

/**
 * HTTP client for the user-search and friendship endpoints of the Ktor backend.
 *
 * ## Endpoints
 * | Method | Path                                  | Description                              |
 * |--------|---------------------------------------|------------------------------------------|
 * | GET    | /api/users/search?q=...               | Search users by username / display name  |
 * | GET    | /api/friends/requests/incoming        | List incoming pending friend requests    |
 * | POST   | /api/friends/request                  | Send a friend request                    |
 * | PATCH  | /api/friends/request/{id}             | Accept or decline a friend request       |
 *
 * ## Authentication
 * Every request includes `Authorization: Bearer <jwt>`. The token is fetched
 * lazily via [tokenProvider] on every call so it is always fresh.
 *
 * When a 401 is received, [onRefreshToken] is called (if provided) to force a
 * token refresh, and the request is retried once. This handles the race condition
 * where a token expires between the proactive expiry check and the server response.
 *
 * @property httpClient      Configured [HttpClient] (from [createHttpClient]).
 * @property backendBaseUrl  Ktor backend base URL, e.g. `https://api.pushup.com`.
 * @property tokenProvider   Returns the current JWT access token.
 * @property onRefreshToken  Optional callback to force a token refresh on 401.
 *                           When provided, a single reactive retry is performed
 *                           after the refresh. When null, 401s are rethrown immediately.
 * @property maxRetries      Max retry attempts for transient errors (default 3).
 */
class FriendshipApiClient(
    private val httpClient: HttpClient,
    private val backendBaseUrl: String,
    private val tokenProvider: suspend () -> String,
    private val onRefreshToken: (suspend () -> Unit)? = null,
    maxRetries: Int = 3,
) : ApiClientBase(maxRetries) {

    /**
     * Executes [block] with retry logic. Uses [withRetryAndTokenRefresh] when
     * [onRefreshToken] is configured, otherwise falls back to [withRetry].
     */
    private suspend fun <T> retrying(block: suspend () -> T): T =
        if (onRefreshToken != null) {
            withRetryAndTokenRefresh(onRefreshToken, block)
        } else {
            withRetry(block)
        }

    /**
     * Searches for users whose username or display name contains [query].
     *
     * Calls `GET /api/users/search?q=<query>`.
     *
     * @param query Search term (minimum 2 characters).
     * @return List of matching [UserSearchResult]s.
     */
    suspend fun searchUsers(query: String): List<UserSearchResult> = retrying {
        val token = tokenProvider()
        httpClient.get("$backendBaseUrl/api/users/search") {
            bearerAuth(token)
            url.parameters.append("q", query)
        }.also { it.expectSuccess() }
            .body<UserSearchResponseDTO>()
            .results
            .map { it.toDomain() }
    }

    /**
     * Returns all incoming pending friend requests for the authenticated user.
     *
     * Calls `GET /api/friends/requests/incoming`.
     *
     * @return List of [FriendRequest]s.
     */
    suspend fun getIncomingFriendRequests(): List<FriendRequest> = retrying {
        val token = tokenProvider()
        httpClient.get("$backendBaseUrl/api/friends/requests/incoming") {
            bearerAuth(token)
        }.also { it.expectSuccess() }
            .body<IncomingFriendRequestsResponseDTO>()
            .requests
            .map { it.toDomain() }
    }

    /**
     * Sends a friend request from the authenticated user to [receiverId].
     *
     * Calls `POST /api/friends/request` with `{ "receiverId": "<uuid>" }`.
     *
     * @param receiverId UUID of the target user.
     * @return The created [Friendship] record.
     */
    suspend fun sendFriendRequest(receiverId: String): Friendship = retrying {
        val token = tokenProvider()
        httpClient.post("$backendBaseUrl/api/friends/request") {
            bearerAuth(token)
            contentType(ContentType.Application.Json)
            setBody(SendFriendRequestDTO(receiverId = receiverId))
        }.also { it.expectSuccess() }
            .body<FriendshipResponseDTO>()
            .toDomain()
    }

    /**
     * Returns all confirmed (accepted) friends of the authenticated user.
     *
     * Calls `GET /api/friends` (default status=accepted).
     *
     * @return List of [Friend]s with basic profile data.
     */
    suspend fun getFriends(): List<Friend> = retrying {
        val token = tokenProvider()
        httpClient.get("$backendBaseUrl/api/friends") {
            bearerAuth(token)
        }.also { it.expectSuccess() }
            .body<FriendsListResponseDTO>()
            .friends
            .map { it.toDomain() }
    }

    /**
     * Returns activity statistics for a specific friend over a given period.
     *
     * Calls `GET /api/friends/{friendId}/stats?period=<period>`.
     *
     * @param friendId UUID of the friend whose stats are requested.
     * @param period   One of "day", "week", or "month".
     * @return [FriendActivityStats] for the requested period.
     * @throws IllegalArgumentException if [friendId] is not a valid UUID.
     */
    suspend fun getFriendStats(friendId: String, period: String): FriendActivityStats {
        require(UUID_REGEX.matches(friendId)) {
            "friendId must be a valid UUID, got: $friendId"
        }
        return retrying {
            val token = tokenProvider()
            httpClient.get("$backendBaseUrl/api/friends/$friendId/stats") {
                bearerAuth(token)
                url.parameters.append("period", period)
            }.also { it.expectSuccess() }
                .body<FriendActivityStatsDTO>()
                .toDomain()
        }
    }

    suspend fun getFriendMonthlyActivity(friendId: String, month: Int, year: Int): FriendMonthlyActivity {
        require(UUID_REGEX.matches(friendId)) {
            "friendId must be a valid UUID, got: $friendId"
        }
        return retrying {
            val token = tokenProvider()
            httpClient.get("$backendBaseUrl/api/friends/$friendId/heatmap") {
                bearerAuth(token)
                url.parameters.append("month", month.toString())
                url.parameters.append("year", year.toString())
            }.also { it.expectSuccess() }
                .body<FriendMonthlyActivityDTO>()
                .toDomain()
        }
    }

    suspend fun getFriendLevelDetails(friendId: String): FriendLevelDetails {
        require(UUID_REGEX.matches(friendId)) {
            "friendId must be a valid UUID, got: $friendId"
        }
        return retrying {
            val token = tokenProvider()
            httpClient.get("$backendBaseUrl/api/friends/$friendId/levels") {
                bearerAuth(token)
            }.also { it.expectSuccess() }
                .body<FriendLevelDetailsDTO>()
                .toDomain()
        }
    }

    /**
     * Removes the friendship between the authenticated user and [friendId].
     *
     * Calls `DELETE /api/friends/{friendId}`.
     *
     * @param friendId UUID of the friend's user account to remove.
     * @throws IllegalArgumentException if [friendId] is not a valid UUID.
     */
    suspend fun removeFriend(friendId: String) {
        require(UUID_REGEX.matches(friendId)) {
            "friendId must be a valid UUID, got: $friendId"
        }
        retrying {
            val token = tokenProvider()
            httpClient.delete("$backendBaseUrl/api/friends/$friendId") {
                bearerAuth(token)
            }.also { it.expectSuccess() }
        }
    }

    /**
     * Accepts or declines a pending friend request.
     *
     * Calls `PATCH /api/friends/request/{friendshipId}` with
     * `{ "status": "accepted" }` or `{ "status": "declined" }`.
     *
     * @param friendshipId UUID of the friendship row to update.
     * @param accept       `true` to accept, `false` to decline.
     * @return The updated [Friendship] record.
     * @throws IllegalArgumentException if [friendshipId] is not a valid UUID.
     */
    suspend fun respondToFriendRequest(friendshipId: String, accept: Boolean): Friendship {
        // Validate UUID format before interpolating into the URL path to prevent
        // path traversal or injection via malformed IDs.
        require(UUID_REGEX.matches(friendshipId)) {
            "friendshipId must be a valid UUID, got: $friendshipId"
        }
        return retrying {
            val token = tokenProvider()
            val status = if (accept) "accepted" else "declined"
            httpClient.patch("$backendBaseUrl/api/friends/request/$friendshipId") {
                bearerAuth(token)
                contentType(ContentType.Application.Json)
                setBody(RespondFriendRequestDTO(status = status))
            }.also { it.expectSuccess() }
                .body<FriendshipResponseDTO>()
                .toDomain()
        }
    }

    companion object {
        /**
         * Regex for validating UUID v4 format before interpolating into URL paths.
         * Prevents path traversal or injection via malformed IDs.
         */
        private val UUID_REGEX = Regex(
            "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        )
    }
}
