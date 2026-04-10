package com.sinura.data.api.dto

import com.sinura.domain.model.AuthToken
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// =============================================================================
// Supabase Auth request bodies
// =============================================================================

/**
 * Request body for email/password sign-up and sign-in.
 *
 * Used for both `POST /auth/v1/signup` and `POST /auth/v1/token?grant_type=password`.
 */
@Serializable
data class EmailPasswordRequest(
    @SerialName("email") val email: String,
    @SerialName("password") val password: String,
)

/**
 * Request body for social (OAuth) sign-in via an ID token.
 *
 * Used for `POST /auth/v1/token?grant_type=id_token`.
 *
 * @property provider The OAuth provider name, e.g. `"apple"` or `"google"`.
 * @property idToken  The identity token issued by the provider.
 */
@Serializable
data class IdTokenRequest(
    @SerialName("provider") val provider: String,
    @SerialName("id_token") val idToken: String,
)

/**
 * Request body for refreshing an access token.
 *
 * Used for `POST /auth/v1/token?grant_type=refresh_token`.
 */
@Serializable
data class RefreshTokenRequest(
    @SerialName("refresh_token") val refreshToken: String,
)

/**
 * Request body for exchanging a PKCE OAuth authorization code for a session.
 *
 * Used for `POST /auth/v1/token?grant_type=pkce`.
 * The [authCode] is the `code` parameter returned in the OAuth redirect URL.
 */
@Serializable
data class OAuthCodeRequest(
    @SerialName("auth_code") val authCode: String,
)

// =============================================================================
// Supabase Auth response bodies
// =============================================================================

/**
 * Response body from Supabase Auth sign-up / sign-in endpoints.
 *
 * Supabase returns a flat JSON object with both the session tokens and the
 * user object embedded. All fields are nullable because some flows (e.g.
 * email confirmation required) may omit the session.
 *
 * @property accessToken  The JWT access token.
 * @property refreshToken The opaque refresh token.
 * @property expiresIn    Seconds until the access token expires.
 * @property tokenType    Always `"bearer"`.
 * @property user         The authenticated user object.
 */
@Serializable
data class AuthSessionDTO(
    @SerialName("access_token")  val accessToken: String? = null,
    @SerialName("refresh_token") val refreshToken: String? = null,
    @SerialName("expires_in")    val expiresIn: Long? = null,
    @SerialName("token_type")    val tokenType: String? = null,
    @SerialName("user")          val user: AuthUserDTO? = null,
)

/**
 * The user object embedded in a Supabase Auth session response.
 *
 * @property id    The Supabase user UUID.
 * @property email The user's email address.
 */
@Serializable
data class AuthUserDTO(
    @SerialName("id")    val id: String,
    @SerialName("email") val email: String? = null,
)

/**
 * Error response body returned by Supabase Auth on failure.
 *
 * @property error            Short error code, e.g. `"invalid_grant"`.
 * @property errorDescription Human-readable description of the error.
 * @property message          Alternative message field used by some endpoints.
 * @property code             Numeric error code used by some endpoints.
 */
@Serializable
data class AuthErrorDTO(
    @SerialName("error")             val error: String? = null,
    @SerialName("error_description") val errorDescription: String? = null,
    @SerialName("message")           val message: String? = null,
    @SerialName("code")              val code: Int? = null,
)

// =============================================================================
// Domain model mappers
// =============================================================================

/**
 * Converts an [AuthSessionDTO] to an [AuthToken] domain model.
 *
 * Throws [com.sinura.domain.model.AuthException.InvalidCredentials] (not
 * [IllegalStateException]) when the session is incomplete so that the error
 * is caught by [com.sinura.data.repository.AuthRepositoryImpl.wrapAuthCall]
 * and surfaced as a typed exception instead of crashing the app.
 *
 * A missing access_token typically means email confirmation is required.
 */
fun AuthSessionDTO.toAuthToken(currentEpochSeconds: Long): AuthToken {
    val access = accessToken?.takeIf { it.isNotBlank() }
        ?: throw com.sinura.domain.model.AuthException.InvalidCredentials(
            "Sign-in succeeded but no session was returned. " +
                "Please confirm your email address first."
        )
    val refresh = refreshToken?.takeIf { it.isNotBlank() }
        ?: throw com.sinura.domain.model.AuthException.InvalidCredentials(
            "Auth session missing refresh_token"
        )
    val uid = user?.id?.takeIf { it.isNotBlank() }
        ?: throw com.sinura.domain.model.AuthException.InvalidCredentials(
            "Auth session missing user.id"
        )
    val expiry = currentEpochSeconds + (expiresIn ?: 3600L)
    return AuthToken(
        accessToken = access,
        refreshToken = refresh,
        userId = uid,
        expiresAt = expiry,
        userEmail = user.email?.takeIf { it.isNotBlank() },
    )
}
