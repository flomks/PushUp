package com.pushup.domain.usecase

import com.pushup.domain.model.RoutePoint
import com.pushup.domain.repository.JoggingSessionRepository
import com.pushup.domain.repository.RoutePointRepository
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/**
 * Use-case: Record a GPS route point during an active jogging session.
 *
 * Validates that the session exists and is still active, then persists the
 * route point and updates the session's running stats (distance, duration, pace).
 *
 * @property sessionRepository Repository for reading and updating jogging sessions.
 * @property routePointRepository Repository for persisting route points.
 * @property clock Clock used for timestamps.
 * @property idGenerator Strategy for generating unique route point IDs.
 */
class RecordRoutePointUseCase(
    private val sessionRepository: JoggingSessionRepository,
    private val routePointRepository: RoutePointRepository,
    private val clock: Clock = Clock.System,
    private val idGenerator: IdGenerator = DefaultIdGenerator,
) {

    /**
     * Records a GPS route point for the given jogging session.
     *
     * @param sessionId The ID of the active jogging session.
     * @param latitude WGS84 latitude in degrees.
     * @param longitude WGS84 longitude in degrees.
     * @param altitude Altitude in meters, or null.
     * @param speed Speed in m/s, or null.
     * @param horizontalAccuracy Horizontal accuracy in meters, or null.
     * @param distanceFromStart Cumulative distance from session start in meters.
     * @param timestamp The timestamp of the GPS fix.
     * @return The persisted [RoutePoint].
     */
    suspend operator fun invoke(
        sessionId: String,
        latitude: Double,
        longitude: Double,
        altitude: Double?,
        speed: Double?,
        horizontalAccuracy: Double?,
        distanceFromStart: Double,
        activeDurationSecondsOverride: Long? = null,
        timestamp: Instant = clock.now(),
    ): RoutePoint {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }

        val session = sessionRepository.getById(sessionId)
            ?: throw SessionNotFoundException("Jogging session '$sessionId' not found")

        if (!session.isActive) {
            throw SessionAlreadyEndedException(
                "Jogging session '$sessionId' has already ended at ${session.endedAt}",
            )
        }

        val routePoint = RoutePoint(
            id = idGenerator.generate(),
            sessionId = sessionId,
            timestamp = timestamp,
            latitude = latitude,
            longitude = longitude,
            altitude = altitude,
            speed = speed,
            horizontalAccuracy = horizontalAccuracy,
            distanceFromStart = distanceFromStart,
        )
        routePointRepository.save(routePoint)

        // Update session running stats
        val durationSeconds = activeDurationSecondsOverride ?: (timestamp - session.startedAt).inWholeSeconds
        val avgPace = if (distanceFromStart >= 100.0) { // Need at least 100m for meaningful pace
            ((durationSeconds.toDouble() / distanceFromStart) * 1000.0).toInt()
        } else {
            null
        }
        val caloriesBurned = estimateCalories(distanceFromStart, durationSeconds)

        sessionRepository.updateStats(
            id = sessionId,
            distanceMeters = distanceFromStart,
            durationSeconds = durationSeconds,
            avgPaceSecondsPerKm = avgPace,
            caloriesBurned = caloriesBurned,
        )

        return routePoint
    }

    /**
     * Simple calorie estimation based on distance.
     * Rough approximation: ~60 calories per km for an average person.
     */
    private fun estimateCalories(distanceMeters: Double, durationSeconds: Long): Int {
        val distanceKm = distanceMeters / 1000.0
        return (distanceKm * 60.0).toInt()
    }
}
