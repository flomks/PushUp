package com.pushup.domain.usecase.auth

import com.pushup.domain.model.AuthException
import com.pushup.domain.model.User
import com.pushup.domain.repository.AuthRepository

/**
 * Use-case: Sign in an existing user with email and password.
 *
 * Validates the input parameters, then delegates to [AuthRepository.loginWithEmail].
 * On success, the session token is stored in secure local storage (iOS Keychain /
 * Android EncryptedSharedPreferences) and the [User] profile is upserted in the
 * local database.
 *
 * ## Validation
 * - [email] must not be blank and must contain `@`.
 * - [password] must not be blank.
 *
 * ## Error handling
 * Throws [AuthException] subclasses on failure:
 * - [AuthException.InvalidCredentials] -- wrong email or password.
 * - [AuthException.NetworkError] -- connectivity issue.
 * - [AuthException.ServerError] -- unexpected server response.
 *
 * @property authRepository The repository that performs the actual sign-in.
 */
class LoginWithEmailUseCase(
    private val authRepository: AuthRepository,
) {

    /**
     * Signs in a user with [email] and [password].
     *
     * @param email    The user's email address.
     * @param password The user's password.
     * @return The authenticated [User].
     * @throws AuthException on failure.
     * @throws IllegalArgumentException if [email] or [password] fail local validation.
     */
    suspend operator fun invoke(email: String, password: String): User {
        require(email.isNotBlank()) { "Email must not be blank" }
        require(email.contains('@')) { "Email must contain '@'" }
        require(password.isNotBlank()) { "Password must not be blank" }
        return authRepository.loginWithEmail(email.trim(), password)
    }
}
