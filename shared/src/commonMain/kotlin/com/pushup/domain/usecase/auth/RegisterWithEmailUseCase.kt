package com.pushup.domain.usecase.auth

import com.pushup.domain.model.AuthException
import com.pushup.domain.model.User
import com.pushup.domain.repository.AuthRepository

/**
 * Use-case: Register a new user with email and password.
 *
 * Validates the input parameters, then delegates to [AuthRepository.registerWithEmail].
 * On success, the session token is stored in secure local storage and the [User]
 * profile is persisted to the local database.
 *
 * ## Validation
 * - [email] must not be blank and must contain `@`.
 * - [password] must be at least [MIN_PASSWORD_LENGTH] characters.
 *
 * ## Error handling
 * Throws [AuthException] subclasses on failure:
 * - [AuthException.InvalidEmail] -- email format is invalid.
 * - [AuthException.WeakPassword] -- password is too short.
 * - [AuthException.EmailAlreadyInUse] -- email is already registered.
 * - [AuthException.NetworkError] -- connectivity issue.
 * - [AuthException.ServerError] -- unexpected server response.
 *
 * @property authRepository The repository that performs the actual registration.
 */
class RegisterWithEmailUseCase(
    private val authRepository: AuthRepository,
) {

    /**
     * Registers a new user with [email] and [password].
     *
     * @param email    The user's email address.
     * @param password The user's chosen password.
     * @return The newly registered [User].
     * @throws AuthException on failure.
     * @throws IllegalArgumentException if [email] or [password] fail local validation.
     */
    suspend operator fun invoke(email: String, password: String): User {
        validateEmail(email)
        validatePassword(password)
        return authRepository.registerWithEmail(email.trim(), password)
    }

    private fun validateEmail(email: String) {
        require(email.isNotBlank()) { "Email must not be blank" }
        require(email.contains('@')) { "Email must contain '@'" }
    }

    private fun validatePassword(password: String) {
        require(password.length >= MIN_PASSWORD_LENGTH) {
            "Password must be at least $MIN_PASSWORD_LENGTH characters"
        }
    }

    companion object {
        /** Minimum password length enforced client-side (mirrors Supabase default). */
        const val MIN_PASSWORD_LENGTH = 6
    }
}
