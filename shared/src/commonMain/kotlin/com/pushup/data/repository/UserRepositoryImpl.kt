package com.pushup.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToOneOrNull
import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.User
import com.pushup.domain.repository.UserRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

/**
 * SQLDelight-backed implementation of [UserRepository].
 *
 * This implementation uses a local-first approach where the device stores
 * a single user profile. [getCurrentUser] returns the first user found
 * (ordered by [User.createdAt] descending).
 *
 * All suspend functions switch to [dispatcher] to keep callers main-safe.
 *
 * @param database The SQLDelight-generated [PushUpDatabase] instance.
 * @param dispatcher The [CoroutineDispatcher] used for database I/O.
 */
class UserRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
) : UserRepository {

    private val queries get() = database.databaseQueries

    override suspend fun getCurrentUser(): User? = withContext(dispatcher) {
        try {
            queries.selectAllUsers().executeAsList().firstOrNull()?.toDomain()
        } catch (e: Exception) {
            throw RepositoryException("Failed to get current user", e)
        }
    }

    override suspend fun saveUser(user: User): Unit = withContext(dispatcher) {
        try {
            queries.insertUser(
                id = user.id,
                email = user.email,
                displayName = user.displayName,
                createdAt = user.createdAt.toEpochMilliseconds(),
                syncedAt = user.lastSyncedAt.toEpochMilliseconds(),
            )
        } catch (e: Exception) {
            throw RepositoryException("Failed to save user '${user.id}'", e)
        }
    }

    override suspend fun updateUser(user: User): Unit = withContext(dispatcher) {
        try {
            queries.updateUser(
                email = user.email,
                displayName = user.displayName,
                syncedAt = user.lastSyncedAt.toEpochMilliseconds(),
                id = user.id,
            )
        } catch (e: Exception) {
            throw RepositoryException("Failed to update user '${user.id}'", e)
        }
    }

    override fun observeCurrentUser(): Flow<User?> =
        queries.selectAllUsers()
            .asFlow()
            .mapToOneOrNull(dispatcher)
            .map { it?.toDomain() }
}
