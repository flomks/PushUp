package com.pushup.data.mapper

import com.pushup.domain.model.AvatarVisibility
import com.pushup.domain.model.User
import kotlinx.datetime.Instant
import com.pushup.db.User as DbUser

/**
 * Converts a SQLDelight [DbUser] entity to a domain [User] model.
 *
 * - `createdAt`: epoch milliseconds [Long] -> [Instant]
 * - `syncedAt`: nullable epoch milliseconds [Long] -> [Instant]
 *   (defaults to [createdAt] when `null`, since the domain model requires a non-null value)
 * - `avatarVisibility`: stored as TEXT, parsed via [AvatarVisibility.fromDbValue]
 */
fun DbUser.toDomain(): User = User(
    id = id,
    email = email,
    username = username,
    displayName = displayName,
    avatarUrl = avatarUrl,
    avatarVisibility = AvatarVisibility.fromDbValue(avatarVisibility),
    createdAt = Instant.fromEpochMilliseconds(createdAt),
    lastSyncedAt = Instant.fromEpochMilliseconds(syncedAt ?: createdAt),
)

/**
 * Converts a domain [User] model to a SQLDelight [DbUser] entity.
 *
 * - `createdAt`: [Instant] -> epoch milliseconds [Long]
 * - `lastSyncedAt`: [Instant] -> epoch milliseconds [Long] (nullable in DB)
 * - `avatarVisibility`: [AvatarVisibility] -> lowercase TEXT
 */
fun User.toDbEntity(): DbUser = DbUser(
    id = id,
    email = email,
    username = username,
    displayName = displayName,
    avatarUrl = avatarUrl,
    avatarVisibility = avatarVisibility.toDbValue(),
    createdAt = createdAt.toEpochMilliseconds(),
    syncedAt = lastSyncedAt.toEpochMilliseconds(),
)
