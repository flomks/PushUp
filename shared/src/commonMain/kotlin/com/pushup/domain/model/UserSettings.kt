package com.pushup.domain.model

import kotlinx.serialization.Serializable

/**
 * User-configurable settings that control how credits are earned.
 *
 * @property userId Identifier of the user these settings belong to.
 * @property pushUpsPerMinuteCredit Number of push-ups required to earn one minute of screen time.
 * @property qualityMultiplierEnabled When `true`, higher-quality push-ups earn bonus credits.
 * @property dailyCreditCapSeconds Optional daily cap on earnable credits (`null` means unlimited).
 */
@Serializable
data class UserSettings(
    val userId: String,
    val pushUpsPerMinuteCredit: Int,
    val qualityMultiplierEnabled: Boolean,
    val dailyCreditCapSeconds: Long?,
) {
    init {
        require(userId.isNotBlank()) { "UserSettings.userId must not be blank" }
        require(pushUpsPerMinuteCredit > 0) {
            "UserSettings.pushUpsPerMinuteCredit must be > 0, was $pushUpsPerMinuteCredit"
        }
        dailyCreditCapSeconds?.let { cap ->
            require(cap > 0) {
                "UserSettings.dailyCreditCapSeconds must be > 0 when set, was $cap"
            }
        }
    }

    companion object {
        /** Sensible defaults for a new user. */
        fun default(userId: String): UserSettings = UserSettings(
            userId = userId,
            pushUpsPerMinuteCredit = 10,
            qualityMultiplierEnabled = true,
            dailyCreditCapSeconds = null,
        )
    }
}
