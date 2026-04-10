package com.sinura.domain.usecase.auth

import com.sinura.domain.model.AuthException
import com.sinura.domain.model.User
import com.sinura.domain.repository.AuthRepository

/**
 * Use-case: Register a new user with email and password.
 *
 * Validates the input parameters, then delegates to [AuthRepository.registerWithEmail].
 * On success, the session token is stored in secure local storage and the [User]
 * profile is persisted to the local database.
 *
 * ## Validation
 * - [email] must not be blank, must contain `@`, must have a non-empty local part
 *   (before `@`) and a non-empty domain part containing at least one `.`.
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
        val trimmed = email.trim()
        val atIndex = trimmed.indexOf('@')
        require(atIndex > 0) { "Email must have a non-empty local part before '@'" }
        val domain = trimmed.substring(atIndex + 1)
        require(domain.contains('.') && domain.length > 2) {
            "Email must have a valid domain (e.g. 'example.com')"
        }
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
