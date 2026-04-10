package com.sinura.domain.usecase.auth

import com.sinura.domain.model.AuthException
import com.sinura.domain.model.User
import com.sinura.domain.repository.AuthRepository

/**
 * Use-case: Sign in (or register) a user using an Apple ID token.
 *
 * The Apple Sign-In flow is handled natively on iOS. This use-case receives
 * the `identityToken` from the `ASAuthorizationAppleIDCredential` and passes
 * it to Supabase Auth via [AuthRepository.loginWithApple].
 *
 * On success, the session token is stored in secure local storage and the
 * [User] profile is upserted in the local database.
 *
 * ## Error handling
 * Throws [AuthException] subclasses on failure:
 * - [AuthException.InvalidCredentials] -- the Apple ID token is invalid or expired.
 * - [AuthException.NetworkError] -- connectivity issue.
 * - [AuthException.ServerError] -- unexpected server response.
 *
 * @property authRepository The repository that performs the actual sign-in.
 */
class LoginWithAppleUseCase(
    private val authRepository: AuthRepository,
) {

    /**
     * Signs in a user using an Apple [idToken].
     *
     * @param idToken The Apple identity token string from `ASAuthorizationAppleIDCredential.identityToken`.
     * @return The authenticated [User].
     * @throws AuthException on failure.
     * @throws IllegalArgumentException if [idToken] is blank.
     */
    suspend operator fun invoke(idToken: String): User {
        require(idToken.isNotBlank()) { "Apple ID token must not be blank" }
        return authRepository.loginWithApple(idToken)
    }
}
