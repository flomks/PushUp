package com.pushup.domain.usecase

import com.pushup.domain.model.UserSettings
import com.pushup.domain.repository.UserSettingsRepository

/**
 * Use-case: Retrieve the current settings for a user.
 *
 * If no settings record exists yet (e.g. a brand-new user who has never
 * configured the app), a default [UserSettings] record is created, persisted,
 * and returned so that callers always receive a non-null value.
 *
 * Default values applied when no record exists:
 * - [UserSettings.pushUpsPerMinuteCredit] = 10
 * - [UserSettings.qualityMultiplierEnabled] = false
 * - [UserSettings.dailyCreditCapSeconds] = null (unlimited)
 *
 * @property settingsRepository Repository for reading and creating settings records.
 */
class GetUserSettingsUseCase(
    private val settingsRepository: UserSettingsRepository,
) {

    /**
     * Returns the settings for the given [userId], creating defaults if none exist.
     *
     * @param userId The ID of the user whose settings to retrieve. Must not be blank.
     * @return The user's [UserSettings], either existing or freshly created defaults.
     * @throws IllegalArgumentException if [userId] is blank.
     */
    suspend operator fun invoke(userId: String): UserSettings {
        require(userId.isNotBlank()) { "userId must not be blank" }

        val existing = settingsRepository.get(userId)
        if (existing != null) return existing

        // No record yet -- create, persist, and return sensible defaults.
        val defaults = UserSettings(
            userId = userId,
            pushUpsPerMinuteCredit = 10,
            qualityMultiplierEnabled = false,
            dailyCreditCapSeconds = null,
        )
        settingsRepository.update(defaults)
        return defaults
    }
}
