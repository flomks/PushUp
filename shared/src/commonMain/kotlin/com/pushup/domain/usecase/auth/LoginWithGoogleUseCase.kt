package com.pushup.domain.usecase.auth

import com.pushup.domain.model.AuthException
import com.pushup.domain.model.User
import com.pushup.domain.repository.AuthRepository

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
}
