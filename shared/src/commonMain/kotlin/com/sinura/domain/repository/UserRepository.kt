package com.sinura.domain.repository

import com.sinura.domain.model.AvatarVisibility
import com.sinura.domain.model.User
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
     * Atomically inserts or replaces the [user] in the data store.
     *
     * Equivalent to SQL `INSERT OR REPLACE`. Safe to call regardless of whether
     * the user already exists -- eliminates the read-then-write TOCTOU race that
     * would occur when calling [saveUser] or [updateUser] conditionally.
     *
     * @param user The user to insert or replace.
     */
    suspend fun upsertUser(user: User)

    /**
     * Deletes the user with [userId] from the data store.
     *
     * All associated data (workout sessions, time credits, settings) is cascade-deleted
     * by the database foreign-key constraints.
     *
     * This is a no-op if no user with [userId] exists.
     *
     * @param userId The ID of the user to delete.
     */
    suspend fun deleteUser(userId: String)

    /**
     * Updates only the [username] field for the user with [userId].
     */
    suspend fun updateUserUsername(userId: String, username: String)

    /**
     * Updates only the [avatarUrl] field for the user with [userId].
     * Pass `null` to clear the avatar (revert to initials fallback).
     */
    suspend fun updateUserAvatar(userId: String, avatarUrl: String?)

    /**
     * Updates only the [avatarVisibility] field for the user with [userId].
     */
    suspend fun updateUserAvatarVisibility(userId: String, visibility: AvatarVisibility)

    /**
     * Observes the currently authenticated user as a reactive [Flow].
     *
     * Emits `null` when no user is signed in.
     */
    fun observeCurrentUser(): Flow<User?>
}
