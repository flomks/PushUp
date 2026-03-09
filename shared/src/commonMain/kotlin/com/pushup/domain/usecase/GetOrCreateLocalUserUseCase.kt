package com.pushup.domain.usecase

import com.pushup.domain.model.AuthException
import com.pushup.domain.model.User
import com.pushup.domain.repository.UserRepository
import kotlinx.datetime.Clock

/**
 * Use-case: Get the currently authenticated local user.
 *
 * Returns the authenticated [User] from the local database.
 * Throws [AuthException.NotAuthenticated] if no user is signed in —
 * the caller must redirect to the login screen in that case.
 *
 * The old "create Guest user" behaviour has been removed. All data
 * is tied to a real Supabase Auth account.
 *
 * @property userRepository Repository used to read the current user.
 */
class GetOrCreateLocalUserUseCase(
    private val userRepository: UserRepository,
    private val clock: Clock = Clock.System,
    private val idGenerator: IdGenerator = DefaultIdGenerator,
) {

    /**
     * Returns the currently authenticated [User].
     *
     * @throws AuthException.NotAuthenticated if no user is signed in.
     */
    suspend operator fun invoke(): User {
        return userRepository.getCurrentUser()
            ?: throw AuthException.NotAuthenticated(
                "No authenticated user found. Please sign in."
            )
    }
}
