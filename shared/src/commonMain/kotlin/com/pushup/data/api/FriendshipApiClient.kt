package com.pushup.data.api

import com.pushup.data.api.dto.FriendshipResponseDTO
import com.pushup.data.api.dto.IncomingFriendRequestsResponseDTO
import com.pushup.data.api.dto.RespondFriendRequestDTO
import com.pushup.data.api.dto.SendFriendRequestDTO
import com.pushup.data.api.dto.UserSearchResponseDTO
import com.pushup.data.api.dto.toDomain
import com.pushup.domain.model.Friendship
import com.pushup.domain.model.FriendRequest
import com.pushup.domain.model.UserSearchResult
import io.ktor.client.HttpClient
import io.ktor.client.call.body
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
 * @property httpClient     Configured [HttpClient] (from [createHttpClient]).
 * @property backendBaseUrl Ktor backend base URL, e.g. `https://api.pushup.com`.
 * @property tokenProvider  Returns the current JWT access token.
 * @property maxRetries     Max retry attempts for transient errors (default 3).
 */
class FriendshipApiClient(
    private val httpClient: HttpClient,
    private val backendBaseUrl: String,
    private val tokenProvider: suspend () -> String,
    maxRetries: Int = 3,
) : ApiClientBase(maxRetries) {

    /**
     * Searches for users whose username or display name contains [query].
     *
     * Calls `GET /api/users/search?q=<query>`.
     *
     * @param query Search term (minimum 2 characters).
     * @return List of matching [UserSearchResult]s.
     */
    suspend fun searchUsers(query: String): List<UserSearchResult> = withRetry {
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
    suspend fun getIncomingFriendRequests(): List<FriendRequest> = withRetry {
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
    suspend fun sendFriendRequest(receiverId: String): Friendship = withRetry {
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
     * Accepts or declines a pending friend request.
     *
     * Calls `PATCH /api/friends/request/{friendshipId}` with
     * `{ "status": "accepted" }` or `{ "status": "declined" }`.
     *
     * @param friendshipId UUID of the friendship row to update.
     * @param accept       `true` to accept, `false` to decline.
     * @return The updated [Friendship] record.
     */
    suspend fun respondToFriendRequest(friendshipId: String, accept: Boolean): Friendship = withRetry {
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
