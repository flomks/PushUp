package com.pushup.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToOneOrNull
import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.UserSettings
import com.pushup.domain.repository.UserSettingsRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map

/**
 * SQLDelight-backed implementation of [UserSettingsRepository].
 *
 * Uses the generated query methods from `Database.sq` and the mappers
 * from [com.pushup.data.mapper] to convert between DB and domain models.
 *
 * The upsert operation is wrapped in a [database.transaction] to prevent
 * race conditions between the row-ID lookup and the INSERT OR REPLACE.
 *
 * All suspend functions are main-safe -- dispatcher switching is handled
 * by [safeDbCall].
 */
class UserSettingsRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
) : UserSettingsRepository {

    private val queries get() = database.databaseQueries

    override suspend fun get(userId: String): UserSettings? = safeDbCall(
        dispatcher,
        "Failed to get settings for user '$userId'",
    ) {
        queries.selectUserSettingsByUserId(userId).executeAsOneOrNull()?.toDomain()
    }

    override suspend fun update(settings: UserSettings): Unit = safeDbCall(
        dispatcher,
        "Failed to update settings for user '${settings.userId}'",
    ) {
        database.transaction {
            val existingRow = queries.selectUserSettingsByUserId(settings.userId)
                .executeAsOneOrNull()
            val rowId = existingRow?.id ?: settings.userId
            queries.upsertUserSettings(
                id = rowId,
                userId = settings.userId,
                pushUpsPerMinuteCredit = settings.pushUpsPerMinuteCredit.toLong(),
                qualityMultiplierEnabled = if (settings.qualityMultiplierEnabled) 1L else 0L,
                dailyCreditCapSeconds = settings.dailyCreditCapSeconds,
                searchableByEmail = if (settings.searchableByEmail) 1L else 0L,
            )
        }
    }

    override fun observeSettings(userId: String): Flow<UserSettings?> =
        queries.selectUserSettingsByUserId(userId)
            .asFlow()
            .mapToOneOrNull(dispatcher)
            .map { it?.toDomain() }
            .catch { e ->
                throw RepositoryException("Failed to observe settings for user '$userId'", e)
            }
}
