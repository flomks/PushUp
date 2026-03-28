package com.pushup.domain.model

import kotlinx.serialization.Serializable

/**
 * User-configurable settings.
 *
 * @property userId                  Identifier of the user these settings belong to.
 * @property pushUpsPerMinuteCredit  Push-ups required to earn one minute of screen time.
 * @property qualityMultiplierEnabled When `true`, higher-quality push-ups earn bonus credits.
 * @property dailyCreditCapSeconds   Optional daily cap on earnable credits (`null` = unlimited).
 * @property searchableByEmail       When `true`, other users can find this account by email.
 *                                   Defaults to `false` (email is private).
 * @property dashboardWidgetOrderJson JSON array of dashboard widget ids. `null` = not set on this device
 *   (seed from cloud on first sync; iOS may show default widgets until the user edits). Explicit empty
 *   dashboard is the string `[]`, not `null`.
 */
@Serializable
data class UserSettings(
    val userId: String,
    val pushUpsPerMinuteCredit: Int,
    val qualityMultiplierEnabled: Boolean,
    val dailyCreditCapSeconds: Long?,
    val searchableByEmail: Boolean = false,
    val dashboardWidgetOrderJson: String? = null,
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
        /**
         * Sensible defaults for a new user.
         */
        fun default(userId: String): UserSettings = UserSettings(
            userId = userId,
            pushUpsPerMinuteCredit = 10,
            qualityMultiplierEnabled = false,
            dailyCreditCapSeconds = null,
            searchableByEmail = false,
        )
    }
}
