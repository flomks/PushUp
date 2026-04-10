package com.sinura.data.mapper

import com.sinura.domain.model.PushUpRecord
import com.sinura.domain.model.SyncStatus
import com.sinura.domain.model.WorkoutSession
import kotlinx.datetime.Instant
import com.sinura.db.PushUpRecord as DbPushUpRecord
import com.sinura.db.WorkoutSession as DbWorkoutSession

// =============================================================================
// WorkoutSession mappers
// =============================================================================

/**
 * Converts a SQLDelight [DbWorkoutSession] entity to a domain [WorkoutSession] model.
 *
 * - `startedAt` / `endedAt`: epoch milliseconds [Long] -> [Instant]
 * - `pushUpCount`: [Long] -> [Int] (with overflow guard)
 * - `quality`: [Double] -> [Float]
 * - `syncStatus`: [String] -> [SyncStatus] enum
 */
fun DbWorkoutSession.toDomain(): WorkoutSession = WorkoutSession(
    id = id,
    userId = userId,
    startedAt = Instant.fromEpochMilliseconds(startedAt),
    endedAt = endedAt?.let { Instant.fromEpochMilliseconds(it) },
    pushUpCount = pushUpCount.toIntChecked("WorkoutSession.pushUpCount"),
    earnedTimeCreditSeconds = earnedTimeCredits,
    quality = quality.toFloat(),
    syncStatus = syncStatusFromString(syncStatus),
)

/**
 * Converts a domain [WorkoutSession] model to a SQLDelight [DbWorkoutSession] entity.
 *
 * @param updatedAt Timestamp for the `updatedAt` column. Callers must supply
 *   this explicitly to keep the mapper pure and deterministic.
 */
fun WorkoutSession.toDbEntity(updatedAt: Instant): DbWorkoutSession = DbWorkoutSession(
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
 * Canonical DB string values for each [SyncStatus] entry.
 *
 * These MUST match the `@SerialName` annotations on [SyncStatus] and the
 * CHECK constraints / default values in the SQLDelight schema (`Database.sq`).
 * If a `@SerialName` value is ever changed, update this map accordingly.
 */
private val syncStatusByDbValue: Map<String, SyncStatus> = mapOf(
    "synced" to SyncStatus.SYNCED,
    "pending" to SyncStatus.PENDING,
    "failed" to SyncStatus.FAILED,
)

private val dbValueBySyncStatus: Map<SyncStatus, String> =
    syncStatusByDbValue.entries.associate { (k, v) -> v to k }

/**
 * Maps a database sync-status string to the [SyncStatus] enum.
 *
 * Known DB values (`"synced"`, `"pending"`, `"failed"`) map to their
 * corresponding enum entries.
 *
 * The DB schema also defines `"syncing"` as a transient state for rows
 * whose upload is in flight. Because the domain layer intentionally has
 * no `SYNCING` variant, in-flight rows are re-queued as [SyncStatus.PENDING]
 * on the next read. This is a deliberate design choice: if the app was
 * killed mid-sync, re-queuing avoids permanently stuck records.
 *
 * Any other unrecognised value also falls back to [SyncStatus.PENDING]
 * for forward-compatibility with future schema additions.
 */
internal fun syncStatusFromString(value: String): SyncStatus =
    syncStatusByDbValue[value] ?: SyncStatus.PENDING

/**
 * Maps a [SyncStatus] enum to its canonical database string representation.
 *
 * The returned string matches the `@SerialName` annotation on the enum entry.
 */
internal fun syncStatusToString(status: SyncStatus): String =
    dbValueBySyncStatus.getValue(status)

// =============================================================================
// Numeric conversion helpers
// =============================================================================

/**
 * Safely narrows a [Long] to [Int] with an explicit overflow check.
 *
 * @param fieldName Human-readable field name for the error message.
 * @throws IllegalStateException if the value exceeds [Int] range.
 */
internal fun Long.toIntChecked(fieldName: String): Int {
    check(this in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) {
        "$fieldName value $this overflows Int range"
    }
    return toInt()
}
