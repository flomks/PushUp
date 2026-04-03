package com.pushup.data.mapper

import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.JoggingPlaybackEntry
import com.pushup.domain.model.JoggingSegment
import com.pushup.domain.model.JoggingSegmentType
import com.pushup.domain.model.RoutePoint
import com.pushup.domain.model.SyncStatus
import kotlinx.datetime.Instant
import com.pushup.db.JoggingPlaybackEntry as DbJoggingPlaybackEntry
import com.pushup.db.JoggingSession as DbJoggingSession
import com.pushup.db.JoggingSegment as DbJoggingSegment
import com.pushup.db.RoutePoint as DbRoutePoint

// =============================================================================
// JoggingSession mappers
// =============================================================================

/**
 * Converts a SQLDelight [DbJoggingSession] entity to a domain [JoggingSession] model.
 */
fun DbJoggingSession.toDomain(): JoggingSession = JoggingSession(
    id = id,
    userId = userId,
    liveRunSessionId = liveRunSessionId,
    startedAt = Instant.fromEpochMilliseconds(startedAt),
    endedAt = endedAt?.let { Instant.fromEpochMilliseconds(it) },
    distanceMeters = distanceMeters,
    durationSeconds = durationSeconds,
    avgPaceSecondsPerKm = avgPaceSecondsPerKm?.toIntChecked("JoggingSession.avgPaceSecondsPerKm"),
    caloriesBurned = caloriesBurned.toIntChecked("JoggingSession.caloriesBurned"),
    earnedTimeCreditSeconds = earnedTimeCredits,
    activeDurationSeconds = activeDurationSeconds,
    pauseDurationSeconds = pauseDurationSeconds,
    activeDistanceMeters = activeDistanceMeters,
    pauseDistanceMeters = pauseDistanceMeters,
    pauseCount = pauseCount.toIntChecked("JoggingSession.pauseCount"),
    syncStatus = syncStatusFromString(syncStatus),
)

/**
 * Converts a domain [JoggingSession] model to a SQLDelight [DbJoggingSession] entity.
 */
fun JoggingSession.toDbEntity(updatedAt: Instant): DbJoggingSession = DbJoggingSession(
    id = id,
    userId = userId,
    liveRunSessionId = liveRunSessionId,
    startedAt = startedAt.toEpochMilliseconds(),
    endedAt = endedAt?.toEpochMilliseconds(),
    distanceMeters = distanceMeters,
    durationSeconds = durationSeconds,
    avgPaceSecondsPerKm = avgPaceSecondsPerKm?.toLong(),
    caloriesBurned = caloriesBurned.toLong(),
    earnedTimeCredits = earnedTimeCreditSeconds,
    activeDurationSeconds = activeDurationSeconds,
    pauseDurationSeconds = pauseDurationSeconds,
    activeDistanceMeters = activeDistanceMeters,
    pauseDistanceMeters = pauseDistanceMeters,
    pauseCount = pauseCount.toLong(),
    syncStatus = syncStatusToString(syncStatus),
    updatedAt = updatedAt.toEpochMilliseconds(),
)

// =============================================================================
// JoggingSegment mappers
// =============================================================================

fun DbJoggingSegment.toDomain(): JoggingSegment = JoggingSegment(
    id = id,
    sessionId = sessionId,
    type = if (type == "pause") JoggingSegmentType.PAUSE else JoggingSegmentType.RUN,
    startedAt = Instant.fromEpochMilliseconds(startedAt),
    endedAt = endedAt?.let { Instant.fromEpochMilliseconds(it) },
    distanceMeters = distanceMeters,
    durationSeconds = durationSeconds,
)

// =============================================================================
// JoggingPlaybackEntry mappers
// =============================================================================

fun DbJoggingPlaybackEntry.toDomain(): JoggingPlaybackEntry = JoggingPlaybackEntry(
    id = id,
    sessionId = sessionId,
    source = source,
    trackTitle = trackTitle,
    artistName = artistName,
    startedAt = Instant.fromEpochMilliseconds(startedAt),
    endedAt = Instant.fromEpochMilliseconds(endedAt),
    startDistanceMeters = startDistanceMeters,
    endDistanceMeters = endDistanceMeters,
    startActiveDurationSeconds = startActiveDurationSeconds,
    endActiveDurationSeconds = endActiveDurationSeconds,
)

// =============================================================================
// RoutePoint mappers
// =============================================================================

/**
 * Converts a SQLDelight [DbRoutePoint] entity to a domain [RoutePoint] model.
 */
fun DbRoutePoint.toDomain(): RoutePoint = RoutePoint(
    id = id,
    sessionId = sessionId,
    timestamp = Instant.fromEpochMilliseconds(timestamp),
    latitude = latitude,
    longitude = longitude,
    altitude = altitude,
    speed = speed,
    horizontalAccuracy = horizontalAccuracy,
    distanceFromStart = distanceFromStart,
)

/**
 * Converts a domain [RoutePoint] model to a SQLDelight [DbRoutePoint] entity.
 */
fun RoutePoint.toDbEntity(): DbRoutePoint = DbRoutePoint(
    id = id,
    sessionId = sessionId,
    timestamp = timestamp.toEpochMilliseconds(),
    latitude = latitude,
    longitude = longitude,
    altitude = altitude,
    speed = speed,
    horizontalAccuracy = horizontalAccuracy,
    distanceFromStart = distanceFromStart,
)
