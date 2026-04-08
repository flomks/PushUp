package com.pushup.data.api.dto

import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.JoggingPlaybackEntry
import com.pushup.domain.model.JoggingSegment
import com.pushup.domain.model.JoggingSegmentType
import com.pushup.domain.model.RoutePoint
import com.pushup.domain.model.SyncStatus
import kotlinx.datetime.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// =============================================================================
// JoggingSession DTOs
// =============================================================================

/**
 * DTO for a jogging session as returned by the Supabase REST API.
 */
@Serializable
data class JoggingSessionDTO(
    @SerialName("id")                       val id: String,
    @SerialName("user_id")                  val userId: String,
    @SerialName("live_run_session_id")      val liveRunSessionId: String? = null,
    @SerialName("started_at")               val startedAt: String,
    @SerialName("ended_at")                 val endedAt: String? = null,
    @SerialName("distance_meters")          val distanceMeters: Float,
    @SerialName("duration_seconds")         val durationSeconds: Int,
    @SerialName("avg_pace_seconds_per_km")  val avgPaceSecondsPerKm: Int? = null,
    @SerialName("calories_burned")          val caloriesBurned: Int,
    @SerialName("earned_time_credits")      val earnedTimeCredits: Int,
    @SerialName("active_duration_seconds")  val activeDurationSeconds: Int = 0,
    @SerialName("pause_duration_seconds")   val pauseDurationSeconds: Int = 0,
    @SerialName("active_distance_meters")   val activeDistanceMeters: Float = 0f,
    @SerialName("pause_distance_meters")    val pauseDistanceMeters: Float = 0f,
    @SerialName("pause_count")              val pauseCount: Int = 0,
    @SerialName("created_at")               val createdAt: String? = null,
    @SerialName("updated_at")               val updatedAt: String? = null,
)

/**
 * Request body for creating a new jogging session via the Supabase REST API.
 */
@Serializable
data class CreateJoggingSessionRequest(
    @SerialName("id")                       val id: String,
    @SerialName("user_id")                  val userId: String,
    @SerialName("live_run_session_id")      val liveRunSessionId: String? = null,
    @SerialName("started_at")               val startedAt: String,
    @SerialName("ended_at")                 val endedAt: String? = null,
    @SerialName("distance_meters")          val distanceMeters: Float = 0f,
    @SerialName("duration_seconds")         val durationSeconds: Int = 0,
    @SerialName("avg_pace_seconds_per_km")  val avgPaceSecondsPerKm: Int? = null,
    @SerialName("calories_burned")          val caloriesBurned: Int = 0,
    @SerialName("earned_time_credits")      val earnedTimeCredits: Int = 0,
    @SerialName("active_duration_seconds")  val activeDurationSeconds: Int = 0,
    @SerialName("pause_duration_seconds")   val pauseDurationSeconds: Int = 0,
    @SerialName("active_distance_meters")   val activeDistanceMeters: Float = 0f,
    @SerialName("pause_distance_meters")    val pauseDistanceMeters: Float = 0f,
    @SerialName("pause_count")              val pauseCount: Int = 0,
)

/**
 * Request body for updating an existing jogging session.
 */
@Serializable
data class UpdateJoggingSessionRequest(
    @SerialName("live_run_session_id")      val liveRunSessionId: String? = null,
    @SerialName("ended_at")                 val endedAt: String? = null,
    @SerialName("distance_meters")          val distanceMeters: Float? = null,
    @SerialName("duration_seconds")         val durationSeconds: Int? = null,
    @SerialName("avg_pace_seconds_per_km")  val avgPaceSecondsPerKm: Int? = null,
    @SerialName("calories_burned")          val caloriesBurned: Int? = null,
    @SerialName("earned_time_credits")      val earnedTimeCredits: Int? = null,
    @SerialName("active_duration_seconds")  val activeDurationSeconds: Int? = null,
    @SerialName("pause_duration_seconds")   val pauseDurationSeconds: Int? = null,
    @SerialName("active_distance_meters")   val activeDistanceMeters: Float? = null,
    @SerialName("pause_distance_meters")    val pauseDistanceMeters: Float? = null,
    @SerialName("pause_count")              val pauseCount: Int? = null,
)

// =============================================================================
// RoutePoint DTOs
// =============================================================================

/**
 * DTO for a single route point as returned by the Supabase REST API.
 */
@Serializable
data class RoutePointDTO(
    @SerialName("id")                   val id: String,
    @SerialName("session_id")           val sessionId: String,
    @SerialName("timestamp")            val timestamp: String,
    @SerialName("latitude")             val latitude: Double,
    @SerialName("longitude")            val longitude: Double,
    @SerialName("altitude")             val altitude: Float? = null,
    @SerialName("speed")                val speed: Float? = null,
    @SerialName("horizontal_accuracy")  val horizontalAccuracy: Float? = null,
    @SerialName("distance_from_start")  val distanceFromStart: Float = 0f,
    @SerialName("created_at")           val createdAt: String? = null,
)

/**
 * Request body for inserting a new route point.
 */
@Serializable
data class CreateRoutePointRequest(
    @SerialName("id")                   val id: String,
    @SerialName("session_id")           val sessionId: String,
    @SerialName("timestamp")            val timestamp: String,
    @SerialName("created_at")           val createdAt: String? = null,
    @SerialName("latitude")             val latitude: Double,
    @SerialName("longitude")            val longitude: Double,
    @SerialName("altitude")             val altitude: Float? = null,
    @SerialName("speed")                val speed: Float? = null,
    @SerialName("horizontal_accuracy")  val horizontalAccuracy: Float? = null,
    @SerialName("distance_from_start")  val distanceFromStart: Float = 0f,
)

@Serializable
data class JoggingSegmentDTO(
    @SerialName("id")                val id: String,
    @SerialName("session_id")        val sessionId: String,
    @SerialName("segment_type")      val segmentType: String,
    @SerialName("started_at")        val startedAt: String,
    @SerialName("ended_at")          val endedAt: String? = null,
    @SerialName("distance_meters")   val distanceMeters: Float = 0f,
    @SerialName("duration_seconds")  val durationSeconds: Int = 0,
)

@Serializable
data class CreateJoggingSegmentRequest(
    @SerialName("id")                val id: String,
    @SerialName("session_id")        val sessionId: String,
    @SerialName("segment_type")      val segmentType: String,
    @SerialName("started_at")        val startedAt: String,
    @SerialName("ended_at")          val endedAt: String? = null,
    @SerialName("created_at")        val createdAt: String? = null,
    @SerialName("distance_meters")   val distanceMeters: Float = 0f,
    @SerialName("duration_seconds")  val durationSeconds: Int = 0,
)

@Serializable
data class JoggingPlaybackEntryDTO(
    @SerialName("id")                             val id: String,
    @SerialName("session_id")                     val sessionId: String,
    @SerialName("source")                         val source: String,
    @SerialName("track_title")                    val trackTitle: String,
    @SerialName("artist_name")                    val artistName: String? = null,
    @SerialName("spotify_track_uri")              val spotifyTrackUri: String? = null,
    @SerialName("started_at")                     val startedAt: String,
    @SerialName("ended_at")                       val endedAt: String,
    @SerialName("start_distance_meters")          val startDistanceMeters: Float = 0f,
    @SerialName("end_distance_meters")            val endDistanceMeters: Float = 0f,
    @SerialName("start_active_duration_seconds")  val startActiveDurationSeconds: Int = 0,
    @SerialName("end_active_duration_seconds")    val endActiveDurationSeconds: Int = 0,
)

@Serializable
data class CreateJoggingPlaybackEntryRequest(
    @SerialName("id")                             val id: String,
    @SerialName("session_id")                     val sessionId: String,
    @SerialName("source")                         val source: String,
    @SerialName("track_title")                    val trackTitle: String,
    @SerialName("artist_name")                    val artistName: String? = null,
    @SerialName("spotify_track_uri")              val spotifyTrackUri: String? = null,
    @SerialName("started_at")                     val startedAt: String,
    @SerialName("ended_at")                       val endedAt: String,
    @SerialName("created_at")                     val createdAt: String? = null,
    @SerialName("start_distance_meters")          val startDistanceMeters: Float = 0f,
    @SerialName("end_distance_meters")            val endDistanceMeters: Float = 0f,
    @SerialName("start_active_duration_seconds")  val startActiveDurationSeconds: Int = 0,
    @SerialName("end_active_duration_seconds")    val endActiveDurationSeconds: Int = 0,
)

// =============================================================================
// Domain model mappers
// =============================================================================

/**
 * Converts a [JoggingSessionDTO] to a [JoggingSession] domain model.
 */
fun JoggingSessionDTO.toDomain(): JoggingSession = JoggingSession(
    id = id,
    userId = userId,
    liveRunSessionId = liveRunSessionId,
    startedAt = Instant.parse(startedAt),
    endedAt = endedAt?.let { Instant.parse(it) },
    distanceMeters = distanceMeters.toDouble(),
    durationSeconds = durationSeconds.toLong(),
    avgPaceSecondsPerKm = avgPaceSecondsPerKm,
    caloriesBurned = caloriesBurned,
    earnedTimeCreditSeconds = earnedTimeCredits.toLong(),
    activeDurationSeconds = activeDurationSeconds.toLong(),
    pauseDurationSeconds = pauseDurationSeconds.toLong(),
    activeDistanceMeters = activeDistanceMeters.toDouble(),
    pauseDistanceMeters = pauseDistanceMeters.toDouble(),
    pauseCount = pauseCount,
    syncStatus = SyncStatus.SYNCED,
)

/**
 * Converts a [JoggingSession] domain model to a [CreateJoggingSessionRequest].
 */
fun JoggingSession.toCreateRequest(): CreateJoggingSessionRequest = CreateJoggingSessionRequest(
    id = id,
    userId = userId,
    liveRunSessionId = liveRunSessionId,
    startedAt = startedAt.toString(),
    endedAt = endedAt?.toString(),
    distanceMeters = distanceMeters.toFloat(),
    durationSeconds = durationSeconds.toInt(),
    avgPaceSecondsPerKm = avgPaceSecondsPerKm,
    caloriesBurned = caloriesBurned,
    earnedTimeCredits = earnedTimeCreditSeconds.toInt(),
    activeDurationSeconds = activeDurationSeconds.toInt(),
    pauseDurationSeconds = pauseDurationSeconds.toInt(),
    activeDistanceMeters = activeDistanceMeters.toFloat(),
    pauseDistanceMeters = pauseDistanceMeters.toFloat(),
    pauseCount = pauseCount,
)

/**
 * Converts a [RoutePointDTO] to a [RoutePoint] domain model.
 */
fun RoutePointDTO.toDomain(): RoutePoint = RoutePoint(
    id = id,
    sessionId = sessionId,
    timestamp = Instant.parse(timestamp),
    latitude = latitude,
    longitude = longitude,
    altitude = altitude?.toDouble(),
    speed = speed?.toDouble(),
    horizontalAccuracy = horizontalAccuracy?.toDouble(),
    distanceFromStart = distanceFromStart.toDouble(),
)

/**
 * Converts a [RoutePoint] domain model to a [CreateRoutePointRequest].
 */
fun RoutePoint.toCreateRequest(): CreateRoutePointRequest = CreateRoutePointRequest(
    id = id,
    sessionId = sessionId,
    timestamp = timestamp.toString(),
    createdAt = timestamp.toString(),
    latitude = latitude,
    longitude = longitude,
    altitude = altitude?.toFloat(),
    speed = speed?.toFloat(),
    horizontalAccuracy = horizontalAccuracy?.toFloat(),
    distanceFromStart = distanceFromStart.toFloat(),
)

fun JoggingSegmentDTO.toDomain(): JoggingSegment = JoggingSegment(
    id = id,
    sessionId = sessionId,
    type = if (segmentType.lowercase() == "pause") JoggingSegmentType.PAUSE else JoggingSegmentType.RUN,
    startedAt = Instant.parse(startedAt),
    endedAt = endedAt?.let { Instant.parse(it) },
    distanceMeters = distanceMeters.toDouble(),
    durationSeconds = durationSeconds.toLong(),
)

fun JoggingSegment.toCreateRequest(): CreateJoggingSegmentRequest = CreateJoggingSegmentRequest(
    id = id,
    sessionId = sessionId,
    segmentType = if (type == JoggingSegmentType.PAUSE) "pause" else "run",
    startedAt = startedAt.toString(),
    endedAt = endedAt?.toString(),
    createdAt = startedAt.toString(),
    distanceMeters = distanceMeters.toFloat(),
    durationSeconds = durationSeconds.toInt(),
)

fun JoggingPlaybackEntryDTO.toDomain(): JoggingPlaybackEntry = JoggingPlaybackEntry(
    id = id,
    sessionId = sessionId,
    source = source,
    trackTitle = trackTitle,
    artistName = artistName,
    spotifyTrackUri = spotifyTrackUri,
    startedAt = Instant.parse(startedAt),
    endedAt = Instant.parse(endedAt),
    startDistanceMeters = startDistanceMeters.toDouble(),
    endDistanceMeters = endDistanceMeters.toDouble(),
    startActiveDurationSeconds = startActiveDurationSeconds.toLong(),
    endActiveDurationSeconds = endActiveDurationSeconds.toLong(),
)

fun JoggingPlaybackEntry.toCreateRequest(): CreateJoggingPlaybackEntryRequest = CreateJoggingPlaybackEntryRequest(
    id = id,
    sessionId = sessionId,
    source = source,
    trackTitle = trackTitle,
    artistName = artistName,
    spotifyTrackUri = spotifyTrackUri,
    startedAt = startedAt.toString(),
    endedAt = endedAt.toString(),
    createdAt = startedAt.toString(),
    startDistanceMeters = startDistanceMeters.toFloat(),
    endDistanceMeters = endDistanceMeters.toFloat(),
    startActiveDurationSeconds = startActiveDurationSeconds.toInt(),
    endActiveDurationSeconds = endActiveDurationSeconds.toInt(),
)

// =============================================================================
// Live Jogging Status DTOs (Presence / Real-time)
// =============================================================================

/**
 * DTO for the live_jogging_status table in Supabase.
 *
 * This is an ephemeral presence record: it exists while a user is actively
 * running and is deleted when the session ends. Designed for Supabase Realtime
 * subscriptions so friends can see who is currently running.
 */
@Serializable
data class LiveJoggingStatusDTO(
    @SerialName("user_id")              val userId: String,
    @SerialName("session_id")           val sessionId: String,
    @SerialName("started_at")           val startedAt: String,
    @SerialName("last_latitude")        val lastLatitude: Double? = null,
    @SerialName("last_longitude")       val lastLongitude: Double? = null,
    @SerialName("last_distance_meters") val lastDistanceMeters: Float = 0f,
    @SerialName("last_duration_seconds") val lastDurationSeconds: Int = 0,
    @SerialName("last_updated_at")      val lastUpdatedAt: String,
)

/**
 * Request body for upserting a live jogging status.
 */
@Serializable
data class UpsertLiveJoggingStatusRequest(
    @SerialName("user_id")              val userId: String,
    @SerialName("session_id")           val sessionId: String,
    @SerialName("started_at")           val startedAt: String,
    @SerialName("last_latitude")        val lastLatitude: Double? = null,
    @SerialName("last_longitude")       val lastLongitude: Double? = null,
    @SerialName("last_distance_meters") val lastDistanceMeters: Float = 0f,
    @SerialName("last_duration_seconds") val lastDurationSeconds: Int = 0,
    @SerialName("last_updated_at")      val lastUpdatedAt: String,
)
