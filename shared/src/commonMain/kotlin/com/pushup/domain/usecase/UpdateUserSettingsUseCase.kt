package com.pushup.domain.usecase

import com.pushup.domain.model.UserSettings
import com.pushup.domain.repository.UserSettingsRepository

/**
 * Use-case: Validate and persist updated user settings.
 *
 * Validation rules (enforced by [UserSettings] itself via `init` checks):
 * - [UserSettings.userId] must not be blank.
 * - [UserSettings.pushUpsPerMinuteCredit] must be > 0.
 * - [UserSettings.dailyCreditCapSeconds], when non-null, must be > 0.
 *
 * If the [UserSettings] object is constructed with invalid values, the
 * [UserSettings] `init` block throws [IllegalArgumentException] before this
 * use-case even receives the object. This use-case therefore only needs to
 * forward the already-validated object to the repository.
 *
 * @property settingsRepository Repository for persisting settings records.
 */
class UpdateUserSettingsUseCase(
    private val settingsRepository: UserSettingsRepository,
) {

    /**
     * Validates and saves the given [settings].
     *
     * Validation is performed by [UserSettings.init]; this method re-validates
     * explicitly to produce clear error messages at the use-case boundary.
     *
     * @param settings The settings to validate and persist.
     * @throws IllegalArgumentException if any field fails validation.
     */
    suspend operator fun invoke(settings: UserSettings) {
        // Re-validate at the use-case boundary for a clear error surface.
        // UserSettings.init already enforces these, but explicit checks here
        // make the use-case self-documenting and testable in isolation.
        require(settings.userId.isNotBlank()) {
            "UserSettings.userId must not be blank"
        }
        require(settings.pushUpsPerMinuteCredit > 0) {
            "pushUpsPerMinuteCredit must be > 0, was ${settings.pushUpsPerMinuteCredit}"
        }
        settings.dailyCreditCapSeconds?.let { cap ->
            require(cap > 0) {
                "dailyCreditCapSeconds must be > 0 when set, was $cap"
            }
        }

        settingsRepository.update(settings)
    }
}
