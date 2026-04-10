package com.sinura.domain.model

import kotlinx.serialization.Serializable

/**
 * Represents a Supabase Auth session token pair.
 *
 * Both tokens are stored securely on-device (iOS: Keychain, Android: EncryptedSharedPreferences).
 * The [accessToken] is a short-lived JWT (typically 1 hour). The [refreshToken] is long-lived
 * and is used by [com.sinura.domain.usecase.auth.RefreshTokenUseCase] to obtain a new
 * [accessToken] when the current one expires.
 *
 * @property accessToken  The JWT used to authenticate API requests.
 * @property refreshToken The opaque token used to obtain a new [accessToken].
 * @property userId       The Supabase user ID associated with this session.
 * @property expiresAt    Unix epoch seconds at which the [accessToken] expires.
 * @property userEmail    The email address returned by the auth server, if available.
 *                        Always present for email/password flows; may be `null` for
 *                        social logins where the provider does not share the email.
 */
@Serializable
data class AuthToken(
    val accessToken: String,
    val refreshToken: String,
    val userId: String,
    val expiresAt: Long,
    val userEmail: String? = null,
) {
    init {
        require(accessToken.isNotBlank()) { "AuthToken.accessToken must not be blank" }
        require(refreshToken.isNotBlank()) { "AuthToken.refreshToken must not be blank" }
        require(userId.isNotBlank()) { "AuthToken.userId must not be blank" }
    }

    /**
     * Returns a redacted string representation that never exposes the raw token values.
     *
     * This prevents accidental token leakage into logs, crash reports, or exception
     * messages when the object is printed or included in a string template.
     */
    override fun toString(): String =
        "AuthToken(userId=$userId, userEmail=$userEmail, expiresAt=$expiresAt, " +
            "accessToken=***REDACTED***, refreshToken=***REDACTED***)"
}
