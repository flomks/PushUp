package com.pushup.domain.model

import kotlinx.serialization.Serializable

/**
 * Represents a Supabase Auth session token pair.
 *
 * Both tokens are stored securely on-device (iOS: Keychain, Android: EncryptedSharedPreferences).
 * The [accessToken] is a short-lived JWT (typically 1 hour). The [refreshToken] is long-lived
 * and is used by [com.pushup.domain.usecase.auth.RefreshTokenUseCase] to obtain a new
 * [accessToken] when the current one expires.
 *
 * @property accessToken  The JWT used to authenticate API requests.
 * @property refreshToken The opaque token used to obtain a new [accessToken].
 * @property userId       The Supabase user ID associated with this session.
 * @property expiresAt    Unix epoch seconds at which the [accessToken] expires.
 */
@Serializable
data class AuthToken(
    val accessToken: String,
    val refreshToken: String,
    val userId: String,
    val expiresAt: Long,
) {
    init {
        require(accessToken.isNotBlank()) { "AuthToken.accessToken must not be blank" }
        require(refreshToken.isNotBlank()) { "AuthToken.refreshToken must not be blank" }
        require(userId.isNotBlank()) { "AuthToken.userId must not be blank" }
    }
}
