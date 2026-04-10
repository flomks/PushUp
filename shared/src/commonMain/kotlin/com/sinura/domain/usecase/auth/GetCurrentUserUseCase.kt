package com.sinura.domain.usecase.auth

import com.sinura.domain.model.User
import com.sinura.domain.repository.AuthRepository

/**
 * Use-case: Get the currently authenticated user.
 *
 * Returns the [User] that is currently signed in, or `null` if no user is
 * authenticated. The user is read from the local database -- no network call
 * is made.
 *
 * This use-case is the primary way for the presentation layer to determine
 * whether the user is authenticated and to access their profile data.
 *
 * ## Typical usage
 * ```kotlin
 * val user = getCurrentUserUseCase()
 * if (user != null) {
 *     // User is authenticated -- show home screen
 * } else {
 *     // No user -- show login screen
 * }
 * ```
 *
 * @property authRepository The repository that provides the current user.
 */
class GetCurrentUserUseCase(
    private val authRepository: AuthRepository,
) {

    /**
     * Returns the currently authenticated [User], or `null` if not signed in.
     *
     * Reads from the local database. Does NOT make a network call.
     */
    suspend operator fun invoke(): User? = authRepository.getCurrentUser()
}
