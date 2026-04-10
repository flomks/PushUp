package com.sinura.domain.usecase.auth

import com.sinura.domain.model.AuthException
import com.sinura.domain.model.User
import com.sinura.domain.repository.AuthRepository

/**
 * Use-case: Sign in (or register) a user using a Google ID token.
 *
 * The Google Sign-In flow is handled natively on Android (via Google Identity
 * Services) and on iOS (via Google Sign-In SDK). This use-case receives the
 * `idToken` from the Google credential and passes it to Supabase Auth via
 * [AuthRepository.loginWithGoogle].
 *
 * On success, the session token is stored in secure local storage and the
 * [User] profile is upserted in the local database.
 *
 * ## Error handling
 * Throws [AuthException] subclasses on failure:
 * - [AuthException.InvalidCredentials] -- the Google ID token is invalid or expired.
 * - [AuthException.NetworkError] -- connectivity issue.
 * - [AuthException.ServerError] -- unexpected server response.
 *
 * @property authRepository The repository that performs the actual sign-in.
 */
class LoginWithGoogleUseCase(
    private val authRepository: AuthRepository,
) {

    /**
     * Signs in a user using a Google [idToken].
     *
     * @param idToken The Google identity token string from the Google Sign-In credential.
     * @return The authenticated [User].
     * @throws AuthException on failure.
     * @throws IllegalArgumentException if [idToken] is blank.
     */
    suspend operator fun invoke(idToken: String): User {
        require(idToken.isNotBlank()) { "Google ID token must not be blank" }
        return authRepository.loginWithGoogle(idToken)
    }

    /**
     * Signs in a user by exchanging a Supabase OAuth PKCE authorization code.
     *
     * Used after the Google OAuth redirect flow (ASWebAuthenticationSession).
     * Supabase returns a `code` parameter in the redirect URL.
     *
     * @param code The authorization code from the OAuth redirect URL.
     * @return The authenticated [User].
     * @throws AuthException on failure.
     */
    suspend fun invokeWithOAuthCode(code: String): User {
        require(code.isNotBlank()) { "OAuth code must not be blank" }
        return authRepository.loginWithOAuthCode(code)
    }
}
