package com.pushup.data.mapper

import com.pushup.domain.model.UserSettings
import com.pushup.db.UserSettings as DbUserSettings

/**
 * Converts a SQLDelight [DbUserSettings] entity to a domain [UserSettings] model.
 *
 * - `pushUpsPerMinuteCredit`: [Long] -> [Int]
 * - `qualityMultiplierEnabled`: [Long] (0/1) -> [Boolean]
 * - `dailyCreditCapSeconds`: nullable [Long] (pass-through)
 *
 * Note: the DB entity carries an `id` column that is not present in the
 * domain model (the domain model uses `userId` as the natural key).
 */
fun DbUserSettings.toDomain(): UserSettings = UserSettings(
    userId = userId,
    pushUpsPerMinuteCredit = pushUpsPerMinuteCredit.toInt(),
    qualityMultiplierEnabled = qualityMultiplierEnabled != 0L,
    dailyCreditCapSeconds = dailyCreditCapSeconds,
)

/**
 * Converts a domain [UserSettings] model to a SQLDelight [DbUserSettings] entity.
 *
 * @param id The primary-key value for the DB row. The domain model does not
 *   carry a separate `id`, so callers must supply one (typically a UUID string).
 */
fun UserSettings.toDbEntity(id: String): DbUserSettings = DbUserSettings(
    id = id,
    userId = userId,
    pushUpsPerMinuteCredit = pushUpsPerMinuteCredit.toLong(),
    qualityMultiplierEnabled = if (qualityMultiplierEnabled) 1L else 0L,
    dailyCreditCapSeconds = dailyCreditCapSeconds,
)
