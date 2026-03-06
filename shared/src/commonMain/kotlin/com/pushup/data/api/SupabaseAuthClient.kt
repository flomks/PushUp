package com.pushup.data.api

import com.pushup.data.api.dto.AuthErrorDTO
import com.pushup.data.api.dto.AuthSessionDTO
import com.pushup.data.api.dto.EmailPasswordRequest
import com.pushup.data.api.dto.IdTokenRequest
import com.pushup.data.api.dto.RefreshTokenRequest
import com.pushup.data.api.dto.toAuthToken
import com.pushup.domain.model.AuthException
import com.pushup.domain.model.AuthToken
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.http.isSuccess
import kotlinx.datetime.Clock
import kotlinx.serialization.json.Json

/**
 * Client for the Supabase Auth REST API (/auth/v1/ endpoints).
 *
 * Handles email/password registration and sign-in, social (Apple/Google) sign-in
 * via ID tokens, and token refresh. All responses are mapped to [AuthToken] domain
 * objects or typed [AuthException] subclasses.
 *
 * ## Endpoints used
 * | Method | Path                                          | Description                  |
 * |--------|-----------------------------------------------|------------------------------|
 * | POST   | /auth/v1/signup                               | Email/password registration  |
 * | POST   | /auth/v1/token?grant_type=password            | Email/password sign-in       |
 * | POST   | /auth/v1/token?grant_type=id_token            | Social (Apple/Google) sign-in|
 * | POST   | /auth/v1/token?grant_type=refresh_token       | Token refresh                |
 *
 * ## Authentication
 * Every request includes the `apikey` header (Supabase anon key). Authenticated
 * requests additionally include `Authorization: Bearer <token>`.
 *
 * @property httpClient      Configured [HttpClient].
 * @property supabaseUrl     Supabase project base URL, e.g. `https://<ref>.supabase.co`.
 * @property supabaseAnonKey Supabase anon (public) API key.
 * @property clock           Used to compute token expiry timestamps.
 */
class SupabaseAuthClient(
    private val httpClient: HttpClient,
    private val supabaseUrl: String,
    private val supabaseAnonKey: String,
    private val clock: Clock = Clock.System,
) : AuthClient {

    private val authBase: String get() = "$supabaseUrl/auth/v1"

    private val lenientJson = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Registers a new user with [email] and [password].
     *
     * Calls `POST /auth/v1/signup`.
     *
     * @return [AuthToken] for the newly created session.
     * @throws AuthException on failure.
     */
    override suspend fun signUpWithEmail(email: String, password: String): AuthToken {
        val response = httpClient.post("$authBase/signup") {
            header("apikey", supabaseAnonKey)
            contentType(ContentType.Application.Json)
            setBody(EmailPasswordRequest(email = email, password = password))
        }
        if (!response.status.isSuccess()) {
            throw mapAuthError(response.status.value, runCatching { response.bodyAsText() }.getOrNull())
        }
        val session = response.body<AuthSessionDTO>()
        return session.toAuthToken(clock.now().epochSeconds)
    }

    /**
     * Signs in an existing user with [email] and [password].
     *
     * Calls `POST /auth/v1/token?grant_type=password`.
     *
     * @return [AuthToken] for the authenticated session.
     * @throws AuthException on failure.
     */
    override suspend fun signInWithEmail(email: String, password: String): AuthToken {
        val response = httpClient.post("$authBase/token") {
            header("apikey", supabaseAnonKey)
            url.parameters.append("grant_type", "password")
            contentType(ContentType.Application.Json)
            setBody(EmailPasswordRequest(email = email, password = password))
        }
        if (!response.status.isSuccess()) {
            throw mapAuthError(response.status.value, runCatching { response.bodyAsText() }.getOrNull())
        }
        val session = response.body<AuthSessionDTO>()
        return session.toAuthToken(clock.now().epochSeconds)
    }

    /**
     * Signs in (or registers) a user using a social provider ID token.
     *
     * Calls `POST /auth/v1/token?grant_type=id_token`.
     *
     * @param provider The OAuth provider name: `"apple"` or `"google"`.
     * @param idToken  The identity token issued by the provider.
     * @return [AuthToken] for the authenticated session.
     * @throws AuthException on failure.
     */
    override suspend fun signInWithIdToken(provider: String, idToken: String): AuthToken {
        val response = httpClient.post("$authBase/token") {
            header("apikey", supabaseAnonKey)
            url.parameters.append("grant_type", "id_token")
            contentType(ContentType.Application.Json)
            setBody(IdTokenRequest(provider = provider, idToken = idToken))
        }
        if (!response.status.isSuccess()) {
            throw mapAuthError(response.status.value, runCatching { response.bodyAsText() }.getOrNull())
        }
        val session = response.body<AuthSessionDTO>()
        return session.toAuthToken(clock.now().epochSeconds)
    }

    /**
     * Refreshes the access token using [refreshToken].
     *
     * Calls `POST /auth/v1/token?grant_type=refresh_token`.
     *
     * @return New [AuthToken] with a fresh access token.
     * @throws AuthException on failure.
     */
    override suspend fun refreshToken(refreshToken: String): AuthToken {
        val response = httpClient.post("$authBase/token") {
            header("apikey", supabaseAnonKey)
            url.parameters.append("grant_type", "refresh_token")
            contentType(ContentType.Application.Json)
            setBody(RefreshTokenRequest(refreshToken = refreshToken))
        }
        if (!response.status.isSuccess()) {
            throw mapAuthError(response.status.value, runCatching { response.bodyAsText() }.getOrNull())
        }
        val session = response.body<AuthSessionDTO>()
        return session.toAuthToken(clock.now().epochSeconds)
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    /**
     * Maps an HTTP error response from Supabase Auth to a typed [AuthException].
     *
     * Supabase Auth uses a mix of HTTP status codes and JSON error bodies to
     * communicate failure reasons. This function inspects both to produce the
     * most specific [AuthException] subclass possible.
     */
    private fun mapAuthError(statusCode: Int, body: String?): AuthException {
        val errorDto = body?.let {
            runCatching { lenientJson.decodeFromString<AuthErrorDTO>(it) }.getOrNull()
        }
        val errorCode = errorDto?.error
        val errorMsg = errorDto?.errorDescription ?: errorDto?.message ?: body ?: "Unknown auth error"

        return when {
            // 422 Unprocessable Entity -- validation errors
            statusCode == HttpStatusCode.UnprocessableEntity.value -> when {
                errorMsg.contains("already registered", ignoreCase = true) ||
                    errorMsg.contains("already in use", ignoreCase = true) ||
                    errorMsg.contains("User already registered", ignoreCase = true) ->
                    AuthException.EmailAlreadyInUse(errorMsg)
                errorMsg.contains("invalid email", ignoreCase = true) ||
                    errorMsg.contains("email address", ignoreCase = true) ->
                    AuthException.InvalidEmail(errorMsg)
                errorMsg.contains("password", ignoreCase = true) ->
                    AuthException.WeakPassword(errorMsg)
                else -> AuthException.ServerError(statusCode, errorMsg)
            }

            // 400 Bad Request -- often invalid credentials or malformed request
            statusCode == HttpStatusCode.BadRequest.value -> when (errorCode) {
                "invalid_grant" -> AuthException.InvalidCredentials(errorMsg)
                else -> when {
                    errorMsg.contains("invalid login credentials", ignoreCase = true) ||
                        errorMsg.contains("invalid credentials", ignoreCase = true) ->
                        AuthException.InvalidCredentials(errorMsg)
                    errorMsg.contains("refresh_token", ignoreCase = true) ||
                        errorMsg.contains("token is expired", ignoreCase = true) ->
                        AuthException.SessionExpired(errorMsg)
                    else -> AuthException.ServerError(statusCode, errorMsg)
                }
            }

            // 401 Unauthorized -- expired or invalid token
            statusCode == HttpStatusCode.Unauthorized.value -> when {
                errorMsg.contains("refresh_token", ignoreCase = true) ||
                    errorMsg.contains("expired", ignoreCase = true) ->
                    AuthException.SessionExpired(errorMsg)
                else -> AuthException.InvalidCredentials(errorMsg)
            }

            // 429 Too Many Requests -- rate limiting (treat as server error)
            statusCode == 429 -> AuthException.ServerError(statusCode, "Too many requests -- please try again later")

            // 5xx Server errors
            statusCode >= 500 -> AuthException.ServerError(statusCode, errorMsg)

            else -> AuthException.Unknown(errorMsg)
        }
    }
}
