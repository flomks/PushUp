package com.pushup.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToOneOrNull
import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.User
import com.pushup.domain.repository.UserRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map

/**
 * SQLDelight-backed implementation of [UserRepository].
 *
 * This implementation uses a local-first approach where the device stores
 * a single user profile. [getCurrentUser] returns the most recently created
 * user via a `LIMIT 1` query.
 *
 * All suspend functions are main-safe -- dispatcher switching is handled
 * by [safeDbCall].
 */
class UserRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
) : UserRepository {

    private val queries get() = database.databaseQueries

    override suspend fun getCurrentUser(): User? = safeDbCall(
        dispatcher,
        "Failed to get current user",
    ) {
        queries.selectCurrentUser().executeAsOneOrNull()?.toDomain()
    }

    override suspend fun saveUser(user: User): Unit = safeDbCall(
        dispatcher,
        "Failed to save user '${user.id}'",
    ) {
        queries.insertUser(
            id = user.id,
            email = user.email,
            username = user.username,
            displayName = user.displayName,
            avatarUrl = user.avatarUrl,
            avatarVisibility = user.avatarVisibility.toDbValue(),
            createdAt = user.createdAt.toEpochMilliseconds(),
            syncedAt = user.lastSyncedAt.toEpochMilliseconds(),
        )
    }

    override suspend fun updateUser(user: User): Unit = safeDbCall(
        dispatcher,
        "Failed to update user '${user.id}'",
    ) {
        queries.updateUser(
            email = user.email,
            username = user.username,
            displayName = user.displayName,
            avatarUrl = user.avatarUrl,
            avatarVisibility = user.avatarVisibility.toDbValue(),
            syncedAt = user.lastSyncedAt.toEpochMilliseconds(),
            id = user.id,
        )
    }

    override suspend fun upsertUser(user: User): Unit = safeDbCall(
        dispatcher,
        "Failed to upsert user '${user.id}'",
    ) {
        queries.upsertUser(
            id = user.id,
            email = user.email,
            username = user.username,
            displayName = user.displayName,
            avatarUrl = user.avatarUrl,
            avatarVisibility = user.avatarVisibility.toDbValue(),
            createdAt = user.createdAt.toEpochMilliseconds(),
            syncedAt = user.lastSyncedAt.toEpochMilliseconds(),
        )
    }

    override suspend fun updateUserUsername(userId: String, username: String): Unit = safeDbCall(
        dispatcher,
        "Failed to update username for user '$userId'",
    ) {
        queries.updateUserUsername(username = username, id = userId)
    }

    override suspend fun updateUserAvatar(userId: String, avatarUrl: String?): Unit = safeDbCall(
        dispatcher,
        "Failed to update avatar for user '$userId'",
    ) {
        queries.updateUserAvatar(avatarUrl = avatarUrl, id = userId)
    }

    override suspend fun updateUserAvatarVisibility(userId: String, visibility: com.pushup.domain.model.AvatarVisibility): Unit = safeDbCall(
        dispatcher,
        "Failed to update avatar visibility for user '$userId'",
    ) {
        queries.updateUserAvatarVisibility(avatarVisibility = visibility.toDbValue(), id = userId)
    }

    override suspend fun deleteUser(userId: String): Unit = safeDbCall(
        dispatcher,
        "Failed to delete user '$userId'",
    ) {
        queries.deleteUser(id = userId)
    }

    override fun observeCurrentUser(): Flow<User?> =
        queries.selectCurrentUser()
            .asFlow()
            .mapToOneOrNull(dispatcher)
            .map { it?.toDomain() }
            .catch { e -> throw RepositoryException("Failed to observe current user", e) }
}
