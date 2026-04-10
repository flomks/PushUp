package com.sinura.data.mapper

import com.sinura.domain.model.SyncStatus
import com.sinura.domain.model.TimeCredit
import kotlinx.datetime.Instant
import com.sinura.db.TimeCredit as DbTimeCredit

/**
 * Converts a SQLDelight [DbTimeCredit] entity to a domain [TimeCredit] model.
 *
 * - `lastUpdatedAt`: epoch milliseconds [Long] -> [Instant]
 * - `lastResetAt`: epoch milliseconds [Long?] -> [Instant?]
 * - `syncStatus`: [String] -> [SyncStatus] enum
 *
 * Note: the DB entity carries an `id` column that is not present in the
 * domain model (the domain model uses `userId` as the natural key).
 */
fun DbTimeCredit.toDomain(): TimeCredit = TimeCredit(
    userId = userId,
    totalEarnedSeconds = totalEarnedSeconds,
    totalSpentSeconds = totalSpentSeconds,
    dailyEarnedSeconds = dailyEarnedSeconds,
    dailySpentSeconds = dailySpentSeconds,
    lastResetAt = lastResetAt?.let { Instant.fromEpochMilliseconds(it) },
    lastUpdatedAt = Instant.fromEpochMilliseconds(lastUpdatedAt),
    syncStatus = syncStatusFromString(syncStatus),
)

/**
 * Converts a domain [TimeCredit] model to a SQLDelight [DbTimeCredit] entity.
 *
 * @param id The primary-key value for the DB row. The domain model does not
 *   carry a separate `id`, so callers must supply one (typically a UUID string).
 */
fun TimeCredit.toDbEntity(id: String): DbTimeCredit = DbTimeCredit(
    id = id,
    userId = userId,
    totalEarnedSeconds = totalEarnedSeconds,
    totalSpentSeconds = totalSpentSeconds,
    dailyEarnedSeconds = dailyEarnedSeconds,
    dailySpentSeconds = dailySpentSeconds,
    lastResetAt = lastResetAt?.toEpochMilliseconds(),
    lastUpdatedAt = lastUpdatedAt.toEpochMilliseconds(),
    syncStatus = syncStatusToString(syncStatus),
)
