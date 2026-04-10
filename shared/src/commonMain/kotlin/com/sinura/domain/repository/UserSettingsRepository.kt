package com.sinura.domain.repository

import com.sinura.domain.model.UserSettings
import kotlinx.coroutines.flow.Flow

/**
 * Repository for managing [UserSettings] entities.
 *
 * Each user has exactly one settings record. If none exists yet,
 * implementations should return sensible defaults (see [UserSettings.default]).
 *
 * Implementations must be **main-safe** -- all dispatcher switching is handled internally.
 */
interface UserSettingsRepository {

    /**
     * Retrieves the settings for the given [userId].
     *
     * @param userId The user whose settings to retrieve.
     * @return The user's settings, or `null` if no record exists.
     */
    suspend fun get(userId: String): UserSettings?

    /**
     * Persists the updated [settings] for the user identified by [UserSettings.userId].
     *
     * @param settings The settings to save.
     */
    suspend fun update(settings: UserSettings)

    /**
     * Observes the settings for the given [userId] as a reactive [Flow].
     *
     * @param userId The user whose settings to observe.
     */
    fun observeSettings(userId: String): Flow<UserSettings?>
}
