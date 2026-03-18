package com.pushup.domain.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

/**
 * Aggregated view of a completed jogging session together with its route
 * points, the credits that were earned, and the XP / level update.
 *
 * This model is used on the post-jogging summary screen.
 *
 * @property session The completed jogging session.
 * @property routePoints All GPS route points captured during the session.
 * @property earnedCredits Total screen-time credit seconds earned in this session.
 * @property earnedXp XP earned in this session (0 when the level system is not active).
 * @property updatedLevel The user's [UserLevel] after XP has been applied, or `null`
 *   if the level system is not yet initialised for this user.
 */
@Serializable
data class JoggingSummary(
    val session: JoggingSession,
    val routePoints: List<RoutePoint>,
    val earnedCredits: Long,
    val earnedXp: Long = 0L,
    val updatedLevel: UserLevel? = null,
) {
    init {
        require(earnedCredits >= 0) {
            "JoggingSummary.earnedCredits must be >= 0, was $earnedCredits"
        }
        require(earnedXp >= 0) {
            "JoggingSummary.earnedXp must be >= 0, was $earnedXp"
        }
        require(routePoints.all { it.sessionId == session.id }) {
            "All RoutePoints must belong to the same session (expected id=${session.id})"
        }
    }

    /** Average speed in km/h across the session, or `0.0` if duration is zero. */
    @Transient
    val averageSpeedKmh: Double =
        if (session.durationSeconds > 0) {
            (session.distanceMeters / 1000.0) / (session.durationSeconds / 3600.0)
        } else {
            0.0
        }

    /** Total number of route points recorded. */
    @Transient
    val routePointCount: Int = routePoints.size
}
