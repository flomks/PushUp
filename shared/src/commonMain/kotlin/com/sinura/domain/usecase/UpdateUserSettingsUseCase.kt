package com.sinura.domain.usecase

import com.sinura.domain.model.UserSettings
import com.sinura.domain.repository.UserSettingsRepository

/**
 * Use-case: Persist updated user settings.
 *
 * All field-level validation is enforced by [UserSettings.init] at construction
 * time, so any [UserSettings] instance received here is already guaranteed to be
 * valid. This use-case is responsible solely for delegating to the repository.
 *
 * Validation rules (enforced by [UserSettings]):
 * - [UserSettings.userId] must not be blank.
 * - [UserSettings.pushUpsPerMinuteCredit] must be > 0.
 * - [UserSettings.dailyCreditCapSeconds], when non-null, must be > 0.
 *
 * @property settingsRepository Repository for persisting settings records.
 */
class UpdateUserSettingsUseCase(
    private val settingsRepository: UserSettingsRepository,
) {

    /**
     * Saves the given [settings].
     *
     * @param settings The settings to persist. Must be a valid [UserSettings] instance.
     */
    suspend operator fun invoke(settings: UserSettings) {
        settingsRepository.update(settings)
    }
}
