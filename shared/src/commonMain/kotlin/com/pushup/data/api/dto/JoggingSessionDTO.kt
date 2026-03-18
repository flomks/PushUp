package com.pushup.data.api.dto

import com.pushup.domain.model.JoggingSession
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
    @SerialName("started_at")               val startedAt: String,
    @SerialName("ended_at")                 val endedAt: String? = null,
    @SerialName("distance_meters")          val distanceMeters: Float,
    @SerialName("duration_seconds")         val durationSeconds: Int,
    @SerialName("avg_pace_seconds_per_km")  val avgPaceSecondsPerKm: Int? = null,
    @SerialName("calories_burned")          val caloriesBurned: Int,
    @SerialName("earned_time_credits")      val earnedTimeCredits: Int,
    @SerialName("created_at")               val createdAt: String? = null,
    @SerialName("updated_at")               val updatedAt: String? = null,
)

/**
 * Request body for creating a new jogging session via the Supabase REST API.
 */
@Serializable
data class CreateJoggingSessionRequest(
    @SerialName("user_id")                  val userId: String,
    @SerialName("started_at")               val startedAt: String,
    @SerialName("ended_at")                 val endedAt: String? = null,
    @SerialName("distance_meters")          val distanceMeters: Float = 0f,
    @SerialName("duration_seconds")         val durationSeconds: Int = 0,
    @SerialName("avg_pace_seconds_per_km")  val avgPaceSecondsPerKm: Int? = null,
    @SerialName("calories_burned")          val caloriesBurned: Int = 0,
    @SerialName("earned_time_credits")      val earnedTimeCredits: Int = 0,
)

/**
 * Request body for updating an existing jogging session.
 */
@Serializable
data class UpdateJoggingSessionRequest(
    @SerialName("ended_at")                 val endedAt: String? = null,
    @SerialName("distance_meters")          val distanceMeters: Float? = null,
    @SerialName("duration_seconds")         val durationSeconds: Int? = null,
    @SerialName("avg_pace_seconds_per_km")  val avgPaceSecondsPerKm: Int? = null,
    @SerialName("calories_burned")          val caloriesBurned: Int? = null,
    @SerialName("earned_time_credits")      val earnedTimeCredits: Int? = null,
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
    @SerialName("session_id")           val sessionId: String,
    @SerialName("timestamp")            val timestamp: String,
    @SerialName("latitude")             val latitude: Double,
    @SerialName("longitude")            val longitude: Double,
    @SerialName("altitude")             val altitude: Float? = null,
    @SerialName("speed")                val speed: Float? = null,
    @SerialName("horizontal_accuracy")  val horizontalAccuracy: Float? = null,
    @SerialName("distance_from_start")  val distanceFromStart: Float = 0f,
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
    startedAt = Instant.parse(startedAt),
    endedAt = endedAt?.let { Instant.parse(it) },
    distanceMeters = distanceMeters.toDouble(),
    durationSeconds = durationSeconds.toLong(),
    avgPaceSecondsPerKm = avgPaceSecondsPerKm,
    caloriesBurned = caloriesBurned,
    earnedTimeCreditSeconds = earnedTimeCredits.toLong(),
    syncStatus = SyncStatus.SYNCED,
)

/**
 * Converts a [JoggingSession] domain model to a [CreateJoggingSessionRequest].
 */
fun JoggingSession.toCreateRequest(): CreateJoggingSessionRequest = CreateJoggingSessionRequest(
    userId = userId,
    startedAt = startedAt.toString(),
    endedAt = endedAt?.toString(),
    distanceMeters = distanceMeters.toFloat(),
    durationSeconds = durationSeconds.toInt(),
    avgPaceSecondsPerKm = avgPaceSecondsPerKm,
    caloriesBurned = caloriesBurned,
    earnedTimeCredits = earnedTimeCreditSeconds.toInt(),
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
    sessionId = sessionId,
    timestamp = timestamp.toString(),
    latitude = latitude,
    longitude = longitude,
    altitude = altitude?.toFloat(),
    speed = speed?.toFloat(),
    horizontalAccuracy = horizontalAccuracy?.toFloat(),
    distanceFromStart = distanceFromStart.toFloat(),
)
