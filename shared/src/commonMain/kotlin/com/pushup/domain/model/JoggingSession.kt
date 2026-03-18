package com.pushup.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

/**
 * Represents a single GPS-tracked jogging workout session.
 *
 * A session begins when the user starts a jog and ends when they stop.
 * GPS route points are recorded during the session to reconstruct the route.
 * Time credits are earned based on distance and duration.
 *
 * @property id Unique identifier for the session.
 * @property userId Identifier of the user who performed the session.
 * @property startedAt Timestamp when the session began.
 * @property endedAt Timestamp when the session ended, or `null` if still in progress.
 * @property distanceMeters Total distance covered in meters.
 * @property durationSeconds Total active duration in seconds.
 * @property avgPaceSecondsPerKm Average pace in seconds per kilometer, or `null` if not enough data.
 * @property caloriesBurned Estimated calories burned during the session.
 * @property earnedTimeCreditSeconds Number of screen-time credit seconds earned.
 * @property syncStatus Current synchronization state with the backend.
 */
@Serializable
data class JoggingSession(
    val id: String,
    val userId: String,
    val startedAt: Instant,
    val endedAt: Instant?,
    val distanceMeters: Double,
    val durationSeconds: Long,
    val avgPaceSecondsPerKm: Int?,
    val caloriesBurned: Int,
    val earnedTimeCreditSeconds: Long,
    val syncStatus: SyncStatus,
) {
    init {
        require(id.isNotBlank()) { "JoggingSession.id must not be blank" }
        require(userId.isNotBlank()) { "JoggingSession.userId must not be blank" }
        require(distanceMeters >= 0.0) { "JoggingSession.distanceMeters must be >= 0, was $distanceMeters" }
        require(durationSeconds >= 0) { "JoggingSession.durationSeconds must be >= 0, was $durationSeconds" }
        require(caloriesBurned >= 0) { "JoggingSession.caloriesBurned must be >= 0, was $caloriesBurned" }
        require(earnedTimeCreditSeconds >= 0) {
            "JoggingSession.earnedTimeCreditSeconds must be >= 0, was $earnedTimeCreditSeconds"
        }
        endedAt?.let { end ->
            require(end >= startedAt) {
                "JoggingSession.endedAt ($end) must not precede startedAt ($startedAt)"
            }
        }
    }

    /** `true` when the session is still being recorded (no [endedAt] yet). */
    val isActive: Boolean get() = endedAt == null

    /** Distance in kilometers (convenience). */
    val distanceKm: Double get() = distanceMeters / 1000.0

    /** Formatted pace as "MM:SS" per km, or "--:--" if not available. */
    val formattedPace: String
        get() {
            val pace = avgPaceSecondsPerKm ?: return "--:--"
            val minutes = pace / 60
            val seconds = pace % 60
            return "${minutes}:${seconds.toString().padStart(2, '0')}"
        }
}
