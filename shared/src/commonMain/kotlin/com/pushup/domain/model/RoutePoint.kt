package com.pushup.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

/**
 * Represents a single GPS coordinate recorded during a [JoggingSession].
 *
 * Route points are recorded at regular intervals during a jog to reconstruct
 * the route on a map. Each point includes location, altitude, speed, and
 * accuracy metadata.
 *
 * @property id Unique identifier for this route point.
 * @property sessionId Identifier of the parent [JoggingSession].
 * @property timestamp The moment this GPS fix was recorded.
 * @property latitude WGS84 latitude in degrees.
 * @property longitude WGS84 longitude in degrees.
 * @property altitude Altitude in meters above sea level, or `null` if unavailable.
 * @property speed Speed in meters per second at this point, or `null` if unavailable.
 * @property horizontalAccuracy Horizontal accuracy radius in meters, or `null` if unavailable.
 * @property distanceFromStart Cumulative distance from the session start in meters.
 */
@Serializable
data class RoutePoint(
    val id: String,
    val sessionId: String,
    val timestamp: Instant,
    val latitude: Double,
    val longitude: Double,
    val altitude: Double?,
    val speed: Double?,
    val horizontalAccuracy: Double?,
    val distanceFromStart: Double,
) {
    init {
        require(id.isNotBlank()) { "RoutePoint.id must not be blank" }
        require(sessionId.isNotBlank()) { "RoutePoint.sessionId must not be blank" }
        require(latitude in -90.0..90.0) { "RoutePoint.latitude must be in [-90, 90], was $latitude" }
        require(longitude in -180.0..180.0) { "RoutePoint.longitude must be in [-180, 180], was $longitude" }
        require(distanceFromStart >= 0.0) { "RoutePoint.distanceFromStart must be >= 0, was $distanceFromStart" }
    }
}
