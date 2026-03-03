package com.pushup.domain.repository

import com.pushup.domain.model.User
import kotlinx.coroutines.flow.Flow

/**
 * Repository for managing [User] entities.
 *
 * Provides access to the currently authenticated user, persistence operations,
 * and a reactive stream for observing user changes.
 *
 * Implementations must be **main-safe** -- all dispatcher switching is handled internally.
 */
interface UserRepository {

    /**
     * Returns the currently authenticated user, or `null` if no user is signed in.
     */
    suspend fun getCurrentUser(): User?

    /**
     * Persists a new [user] to the data store.
     *
     * @param user The user to save.
     */
    suspend fun saveUser(user: User)

    /**
     * Updates an existing [user] in the data store.
     *
     * @param user The user with updated fields (matched by [User.id]).
     */
    suspend fun updateUser(user: User)

    /**
     * Observes the currently authenticated user as a reactive [Flow].
     *
     * Emits `null` when no user is signed in.
     */
    fun observeCurrentUser(): Flow<User?>
}
