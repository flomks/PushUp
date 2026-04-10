package com.sinura.data.api

import com.sinura.data.api.dto.AuthErrorDTO
import com.sinura.data.api.dto.AuthSessionDTO
import com.sinura.data.api.dto.EmailPasswordRequest
import com.sinura.data.api.dto.IdTokenRequest
import com.sinura.data.api.dto.OAuthCodeRequest
import com.sinura.data.api.dto.RefreshTokenRequest
import com.sinura.data.api.dto.toAuthToken
import com.sinura.domain.model.AuthException
import com.sinura.domain.model.AuthToken
import com.sinura.domain.model.SocialProvider
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
 * Every request includes the `apikey` header (Supabase publishable key).
 * Authenticated requests additionally include `Authorization: Bearer <token>`.
 *
 * @property httpClient             Configured [HttpClient].
 * @property supabaseUrl            Supabase project base URL, e.g. `https://<ref>.supabase.co`.
 * @property supabasePublishableKey Supabase publishable (public) API key.
 *                                  Previously called the "anon key".
 * @property clock                  Used to compute token expiry timestamps.
 */
class SupabaseAuthClient(
    private val httpClient: HttpClient,
    private val supabaseUrl: String,
    private val supabasePublishableKey: String,
    private val clock: Clock = Clock.System,
) : AuthClient {

    private val authBase: String get() = "$supabaseUrl/auth/v1"

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
            header("apikey", supabasePublishableKey)
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
            header("apikey", supabasePublishableKey)
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
     * @param provider The OAuth provider (typed enum -- prevents typos).
     * @param idToken  The identity token issued by the provider.
     * @return [AuthToken] for the authenticated session.
     * @throws AuthException on failure.
     */
    override suspend fun signInWithIdToken(provider: SocialProvider, idToken: String): AuthToken {
        val response = httpClient.post("$authBase/token") {
            header("apikey", supabasePublishableKey)
            url.parameters.append("grant_type", "id_token")
            contentType(ContentType.Application.Json)
            setBody(IdTokenRequest(provider = provider.apiValue, idToken = idToken))
        }
        if (!response.status.isSuccess()) {
            throw mapAuthError(response.status.value, runCatching { response.bodyAsText() }.getOrNull())
        }
        val session = response.body<AuthSessionDTO>()
        return session.toAuthToken(clock.now().epochSeconds)
    }

    /**
     * Exchanges a Supabase OAuth PKCE authorization code for a session token.
     *
     * Calls `POST /auth/v1/token?grant_type=pkce`.
     *
     * @param code The authorization code from the OAuth redirect URL `?code=` parameter.
     * @return [AuthToken] for the authenticated session.
     * @throws AuthException on failure.
     */
    override suspend fun exchangeOAuthCode(code: String): AuthToken {
        val response = httpClient.post("$authBase/token") {
            header("apikey", supabasePublishableKey)
            url.parameters.append("grant_type", "pkce")
            contentType(ContentType.Application.Json)
            setBody(OAuthCodeRequest(authCode = code))
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
            header("apikey", supabasePublishableKey)
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
     * Prefers structured error codes (`errorDto.error`, `errorDto.code`) over
     * free-text message matching. Falls back to message matching only for codes
     * that Supabase does not yet expose as structured fields.
     *
     * Supabase v2 error codes reference:
     * https://supabase.com/docs/reference/javascript/auth-error-codes
     */
    private fun mapAuthError(statusCode: Int, body: String?): AuthException {
        val errorDto = body?.let {
            runCatching { errorJson.decodeFromString<AuthErrorDTO>(it) }.getOrNull()
        }
        val errorCode = errorDto?.error
        // Prefer structured description; fall back to raw body (truncated for safety)
        val errorMsg = errorDto?.errorDescription
            ?: errorDto?.message
            ?: body?.take(200)
            ?: "Unknown auth error"

        return when {
            // 422 Unprocessable Entity -- validation errors
            statusCode == HttpStatusCode.UnprocessableEntity.value -> when {
                // Supabase structured codes (preferred)
                errorCode == "user_already_exists" ->
                    AuthException.EmailAlreadyInUse(errorMsg)
                errorCode == "email_exists" ->
                    AuthException.EmailAlreadyInUse(errorMsg)
                errorCode == "weak_password" ->
                    AuthException.WeakPassword(errorMsg)
                errorCode == "invalid_email" ->
                    AuthException.InvalidEmail(errorMsg)
                // Fallback message matching for older Supabase versions
                errorMsg.contains("already registered", ignoreCase = true) ||
                    errorMsg.contains("already in use", ignoreCase = true) ->
                    AuthException.EmailAlreadyInUse(errorMsg)
                errorMsg.contains("password", ignoreCase = true) ->
                    AuthException.WeakPassword(errorMsg)
                errorMsg.contains("email", ignoreCase = true) ->
                    AuthException.InvalidEmail(errorMsg)
                else -> AuthException.ServerError(statusCode, sanitise(errorMsg))
            }

            // 400 Bad Request -- invalid credentials or malformed request
            statusCode == HttpStatusCode.BadRequest.value -> when (errorCode) {
                "invalid_grant" -> AuthException.InvalidCredentials(errorMsg)
                "session_not_found" -> AuthException.SessionExpired(errorMsg)
                else -> when {
                    errorMsg.contains("invalid login credentials", ignoreCase = true) ||
                        errorMsg.contains("invalid credentials", ignoreCase = true) ->
                        AuthException.InvalidCredentials(errorMsg)
                    errorMsg.contains("refresh_token", ignoreCase = true) ||
                        errorMsg.contains("token is expired", ignoreCase = true) ->
                        AuthException.SessionExpired(errorMsg)
                    else -> AuthException.ServerError(statusCode, sanitise(errorMsg))
                }
            }

            // 401 Unauthorized -- expired or invalid token
            statusCode == HttpStatusCode.Unauthorized.value -> when {
                errorCode == "session_not_found" -> AuthException.SessionExpired(errorMsg)
                errorMsg.contains("refresh_token", ignoreCase = true) ||
                    errorMsg.contains("expired", ignoreCase = true) ->
                    AuthException.SessionExpired(errorMsg)
                else -> AuthException.InvalidCredentials(errorMsg)
            }

            // 429 Too Many Requests -- rate limiting
            statusCode == 429 ->
                AuthException.ServerError(statusCode, "Too many requests -- please try again later")

            // 5xx Server errors
            statusCode >= 500 -> AuthException.ServerError(statusCode, sanitise(errorMsg))

            else -> AuthException.Unknown(sanitise(errorMsg))
        }
    }

    /**
     * Truncates and sanitises a server message before embedding it in an exception.
     *
     * Prevents raw server response bodies (which may contain internal details or
     * user data) from being surfaced verbatim in logs or crash reports.
     */
    private fun sanitise(msg: String): String = msg.take(200)

    private companion object {
        /**
         * Shared lenient [Json] instance for parsing Supabase Auth error bodies.
         *
         * Uses `ignoreUnknownKeys` and `isLenient` for resilience against minor
         * format variations. Declared as a companion object constant to avoid
         * allocating a new instance per request.
         */
        val errorJson = Json {
            ignoreUnknownKeys = true
            isLenient = true
        }
    }
}
