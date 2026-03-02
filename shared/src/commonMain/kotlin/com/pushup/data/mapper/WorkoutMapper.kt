package com.pushup.data.mapper

import com.pushup.domain.model.PushUpRecord
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.WorkoutSession
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import com.pushup.db.PushUpRecord as DbPushUpRecord
import com.pushup.db.WorkoutSession as DbWorkoutSession

// =============================================================================
// WorkoutSession mappers
// =============================================================================

/**
 * Converts a SQLDelight [DbWorkoutSession] entity to a domain [WorkoutSession] model.
 *
 * - `startedAt` / `endedAt`: epoch milliseconds [Long] -> [Instant]
 * - `pushUpCount`: [Long] -> [Int]
 * - `quality`: [Double] -> [Float]
 * - `syncStatus`: [String] -> [SyncStatus] enum
 */
fun DbWorkoutSession.toDomain(): WorkoutSession = WorkoutSession(
    id = id,
    userId = userId,
    startedAt = Instant.fromEpochMilliseconds(startedAt),
    endedAt = endedAt?.let { Instant.fromEpochMilliseconds(it) },
    pushUpCount = pushUpCount.toInt(),
    earnedTimeCreditSeconds = earnedTimeCredits,
    quality = quality.toFloat(),
    syncStatus = syncStatusFromString(syncStatus),
)

/**
 * Converts a domain [WorkoutSession] model to a SQLDelight [DbWorkoutSession] entity.
 *
 * @param updatedAt Timestamp for the `updatedAt` column. Defaults to [Clock.System.now].
 */
fun WorkoutSession.toDbEntity(
    updatedAt: Instant = Clock.System.now(),
): DbWorkoutSession = DbWorkoutSession(
    id = id,
    userId = userId,
    startedAt = startedAt.toEpochMilliseconds(),
    endedAt = endedAt?.toEpochMilliseconds(),
    pushUpCount = pushUpCount.toLong(),
    earnedTimeCredits = earnedTimeCreditSeconds,
    quality = quality.toDouble(),
    syncStatus = syncStatusToString(syncStatus),
    updatedAt = updatedAt.toEpochMilliseconds(),
)

// =============================================================================
// PushUpRecord mappers
// =============================================================================

/**
 * Converts a SQLDelight [DbPushUpRecord] entity to a domain [PushUpRecord] model.
 *
 * - `timestamp`: epoch milliseconds [Long] -> [Instant]
 * - `depthScore` / `formScore`: [Double] -> [Float]
 */
fun DbPushUpRecord.toDomain(): PushUpRecord = PushUpRecord(
    id = id,
    sessionId = sessionId,
    timestamp = Instant.fromEpochMilliseconds(timestamp),
    durationMs = durationMs,
    depthScore = depthScore.toFloat(),
    formScore = formScore.toFloat(),
)

/**
 * Converts a domain [PushUpRecord] model to a SQLDelight [DbPushUpRecord] entity.
 *
 * - `timestamp`: [Instant] -> epoch milliseconds [Long]
 * - `depthScore` / `formScore`: [Float] -> [Double]
 */
fun PushUpRecord.toDbEntity(): DbPushUpRecord = DbPushUpRecord(
    id = id,
    sessionId = sessionId,
    timestamp = timestamp.toEpochMilliseconds(),
    durationMs = durationMs,
    depthScore = depthScore.toDouble(),
    formScore = formScore.toDouble(),
)

// =============================================================================
// SyncStatus helpers
// =============================================================================

/**
 * Maps a database sync-status string to the [SyncStatus] enum.
 *
 * Falls back to [SyncStatus.PENDING] for unrecognised values so that
 * forward-compatible DB rows (e.g. `'syncing'`) don't crash the app.
 */
internal fun syncStatusFromString(value: String): SyncStatus = when (value) {
    "synced" -> SyncStatus.SYNCED
    "pending" -> SyncStatus.PENDING
    "failed" -> SyncStatus.FAILED
    else -> SyncStatus.PENDING
}

/**
 * Maps a [SyncStatus] enum to its canonical database string representation.
 */
internal fun syncStatusToString(status: SyncStatus): String = when (status) {
    SyncStatus.SYNCED -> "synced"
    SyncStatus.PENDING -> "pending"
    SyncStatus.FAILED -> "failed"
}
