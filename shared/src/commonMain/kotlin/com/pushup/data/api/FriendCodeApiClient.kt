package com.pushup.data.api

import com.pushup.data.api.dto.FriendCodeResponseDTO
import com.pushup.data.api.dto.UpdateFriendCodePrivacyDTO
import com.pushup.data.api.dto.UseFriendCodeRequestDTO
import com.pushup.data.api.dto.UseFriendCodeResponseDTO
import com.pushup.data.api.dto.toDomain
import com.pushup.domain.model.FriendCode
import com.pushup.domain.model.FriendCodePrivacy
import com.pushup.domain.model.UseFriendCodeResult
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.patch
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType

/**
 * HTTP client for the friend code endpoints of the Ktor backend.
 *
 * ## Endpoints
 * | Method | Path                          | Description                                  |
 * |--------|-------------------------------|----------------------------------------------|
 * | GET    | /api/friend-code              | Get (or create) the caller's friend code     |
 * | PATCH  | /api/friend-code/privacy      | Update the privacy setting                   |
 * | POST   | /api/friend-code/reset        | Generate a new random code                   |
 * | POST   | /api/friend-code/use          | Use a friend code to add/request a friend    |
 *
 * @property httpClient      Configured [HttpClient].
 * @property backendBaseUrl  Ktor backend base URL.
 * @property tokenProvider   Returns the current JWT access token.
 * @property onRefreshToken  Optional callback to force a token refresh on 401.
 * @property maxRetries      Max retry attempts for transient errors (default 3).
 */
class FriendCodeApiClient(
    private val httpClient: HttpClient,
    private val backendBaseUrl: String,
    private val tokenProvider: suspend () -> String,
    private val onRefreshToken: (suspend () -> Unit)? = null,
    maxRetries: Int = 3,
) : ApiClientBase(maxRetries) {

    private suspend fun <T> retrying(block: suspend () -> T): T =
        if (onRefreshToken != null) {
            withRetryAndTokenRefresh(onRefreshToken, block)
        } else {
            withRetry(block)
        }

    /**
     * Returns (or creates) the authenticated user's friend code.
     *
     * Calls `GET /api/friend-code`.
     */
    suspend fun getMyFriendCode(): FriendCode = retrying {
        val token = tokenProvider()
        httpClient.get("$backendBaseUrl/api/friend-code") {
            bearerAuth(token)
        }.also { it.expectSuccess() }
            .body<FriendCodeResponseDTO>()
            .toDomain()
    }

    /**
     * Updates the privacy setting of the authenticated user's friend code.
     *
     * Calls `PATCH /api/friend-code/privacy`.
     *
     * @param privacy The desired new privacy setting.
     */
    suspend fun updatePrivacy(privacy: FriendCodePrivacy): FriendCode = retrying {
        val token = tokenProvider()
        val privacyValue = when (privacy) {
            FriendCodePrivacy.AUTO_ACCEPT      -> "auto_accept"
            FriendCodePrivacy.REQUIRE_APPROVAL -> "require_approval"
            FriendCodePrivacy.INACTIVE         -> "inactive"
        }
        httpClient.patch("$backendBaseUrl/api/friend-code/privacy") {
            bearerAuth(token)
            contentType(ContentType.Application.Json)
            setBody(UpdateFriendCodePrivacyDTO(privacy = privacyValue))
        }.also { it.expectSuccess() }
            .body<FriendCodeResponseDTO>()
            .toDomain()
    }

    /**
     * Generates a new random code for the authenticated user.
     *
     * Calls `POST /api/friend-code/reset`.
     */
    suspend fun resetCode(): FriendCode = retrying {
        val token = tokenProvider()
        httpClient.post("$backendBaseUrl/api/friend-code/reset") {
            bearerAuth(token)
        }.also { it.expectSuccess() }
            .body<FriendCodeResponseDTO>()
            .toDomain()
    }

    /**
     * Uses a friend code entered or scanned by the authenticated user.
     *
     * Calls `POST /api/friend-code/use`.
     *
     * @param code The friend code string.
     */
    suspend fun useFriendCode(code: String): UseFriendCodeResult = retrying {
        val token = tokenProvider()
        httpClient.post("$backendBaseUrl/api/friend-code/use") {
            bearerAuth(token)
            contentType(ContentType.Application.Json)
            setBody(UseFriendCodeRequestDTO(code = code))
        }.also { it.expectSuccess() }
            .body<UseFriendCodeResponseDTO>()
            .toDomain()
    }
}
