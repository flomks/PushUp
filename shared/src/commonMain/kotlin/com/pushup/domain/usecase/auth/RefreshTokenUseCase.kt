package com.pushup.domain.usecase.auth

import com.pushup.domain.model.AuthException
import com.pushup.domain.model.AuthToken
import com.pushup.domain.repository.AuthRepository

/**
 * Use-case: Refresh the expired access token using the stored refresh token.
 *
 * Calls the Supabase Auth token refresh endpoint and stores the new tokens
 * in secure local storage. This use-case is typically called automatically
 * by the [com.pushup.data.api.JwtTokenProvider] when it detects that the
 * current access token has expired.
 *
 * ## When to use
 * - When an API call returns HTTP 401 (Unauthorized) due to an expired token.
 * - Proactively, before making an API call, if the token's [AuthToken.expiresAt]
 *   is in the past or within a short buffer window.
 *
 * ## Error handling
 * Throws [AuthException] subclasses on failure:
 * - [AuthException.NotAuthenticated] -- no refresh token is stored (user is not logged in).
 * - [AuthException.SessionExpired] -- the refresh token itself has expired or been revoked.
 *   The user must re-authenticate from scratch.
 * - [AuthException.NetworkError] -- connectivity issue.
 * - [AuthException.ServerError] -- unexpected server response.
 *
 * @property authRepository The repository that manages token storage and refresh.
 */
class RefreshTokenUseCase(
    private val authRepository: AuthRepository,
) {

    /**
     * Refreshes the access token and returns the new [AuthToken].
     *
     * @return The new [AuthToken] with a fresh access token and updated expiry.
     * @throws AuthException on failure.
     */
    suspend operator fun invoke(): AuthToken = authRepository.refreshToken()
}
