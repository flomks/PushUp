package com.pushup.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToOneOrNull
import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.UserSettings
import com.pushup.domain.repository.UserSettingsRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

/**
 * SQLDelight-backed implementation of [UserSettingsRepository].
 *
 * Uses the generated query methods from `Database.sq` and the mappers
 * from [com.pushup.data.mapper] to convert between DB and domain models.
 *
 * The DB schema stores a separate `id` primary key per UserSettings row,
 * while the domain model uses `userId` as the natural key. This
 * implementation uses `userId` as the `id` for upsert operations.
 *
 * All suspend functions switch to [dispatcher] to keep callers main-safe.
 *
 * @param database The SQLDelight-generated [PushUpDatabase] instance.
 * @param dispatcher The [CoroutineDispatcher] used for database I/O.
 */
class UserSettingsRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
) : UserSettingsRepository {

    private val queries get() = database.databaseQueries

    override suspend fun get(userId: String): UserSettings? = withContext(dispatcher) {
        try {
            queries.selectUserSettingsByUserId(userId).executeAsOneOrNull()?.toDomain()
        } catch (e: Exception) {
            throw RepositoryException("Failed to get settings for user '$userId'", e)
        }
    }

    override suspend fun update(settings: UserSettings): Unit = withContext(dispatcher) {
        try {
            val existingRow = queries.selectUserSettingsByUserId(settings.userId)
                .executeAsOneOrNull()
            val rowId = existingRow?.id ?: settings.userId
            queries.upsertUserSettings(
                id = rowId,
                userId = settings.userId,
                pushUpsPerMinuteCredit = settings.pushUpsPerMinuteCredit.toLong(),
                qualityMultiplierEnabled = if (settings.qualityMultiplierEnabled) 1L else 0L,
                dailyCreditCapSeconds = settings.dailyCreditCapSeconds,
            )
        } catch (e: Exception) {
            throw RepositoryException(
                "Failed to update settings for user '${settings.userId}'",
                e,
            )
        }
    }

    override fun observeSettings(userId: String): Flow<UserSettings?> =
        queries.selectUserSettingsByUserId(userId)
            .asFlow()
            .mapToOneOrNull(dispatcher)
            .map { it?.toDomain() }
}
