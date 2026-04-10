package com.sinura.service

import com.sinura.plugins.JoggingSessions
import com.sinura.plugins.RoutePoints
import org.jetbrains.exposed.sql.SortOrder
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.greaterEq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.isNotNull
import org.jetbrains.exposed.sql.SqlExpressionBuilder.less
import org.jetbrains.exposed.sql.and
import org.jetbrains.exposed.sql.avg
import org.jetbrains.exposed.sql.count
import org.jetbrains.exposed.sql.max
import org.jetbrains.exposed.sql.sum
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID

/**
 * Service for querying aggregated jogging statistics from PostgreSQL.
 *
 * Follows the same pattern as [StatsService] for push-up workouts.
 */
class JoggingStatsService {

    // Aggregate expressions
    private val distanceSum = JoggingSessions.distanceMeters.sum()
    private val durationSum = JoggingSessions.durationSeconds.sum()
    private val caloriesSum = JoggingSessions.caloriesBurned.sum()
    private val creditsSum = JoggingSessions.earnedTimeCredits.sum()
    private val sessionCount = JoggingSessions.id.count()
    private val bestDistanceExpr = JoggingSessions.distanceMeters.max()

    /**
     * Returns total jogging stats for a user.
     */
    suspend fun getTotalStats(userId: UUID): JoggingTotalStatsDTO = newSuspendedTransaction {
        val row = JoggingSessions
            .select(distanceSum, durationSum, caloriesSum, creditsSum, sessionCount, bestDistanceExpr)
            .where {
                (JoggingSessions.userId eq userId) and
                    JoggingSessions.endedAt.isNotNull()
            }
            .firstOrNull()

        if (row == null) return@newSuspendedTransaction emptyTotalStats()

        val sessions = row[sessionCount].toInt()
        val totalDistance = row[distanceSum]?.toDouble() ?: 0.0
        val totalDuration = row[durationSum]?.toLong() ?: 0L

        val avgPace = if (totalDistance >= 1000.0 && totalDuration > 0) {
            ((totalDuration.toDouble() / totalDistance) * 1000.0).toInt()
        } else {
            null
        }

        JoggingTotalStatsDTO(
            totalDistanceMeters = totalDistance,
            totalDurationSeconds = totalDuration,
            totalSessions = sessions,
            totalCaloriesBurned = row[caloriesSum] ?: 0,
            totalEarnedSeconds = (row[creditsSum] ?: 0).toLong(),
            avgPaceSecondsPerKm = avgPace,
            bestDistanceMeters = row[bestDistanceExpr]?.toDouble(),
        )
    }

    /**
     * Returns all jogging sessions for a user, newest first.
     */
    suspend fun getSessionHistory(userId: UUID): List<JoggingSessionHistoryDTO> = newSuspendedTransaction {
        JoggingSessions
            .select(
                JoggingSessions.id,
                JoggingSessions.startedAt,
                JoggingSessions.endedAt,
                JoggingSessions.distanceMeters,
                JoggingSessions.durationSeconds,
                JoggingSessions.avgPaceSecondsPerKm,
                JoggingSessions.caloriesBurned,
                JoggingSessions.earnedTimeCredits,
            )
            .where {
                (JoggingSessions.userId eq userId) and
                    JoggingSessions.endedAt.isNotNull()
            }
            .orderBy(JoggingSessions.startedAt to SortOrder.DESC)
            .map { row ->
                JoggingSessionHistoryDTO(
                    id = row[JoggingSessions.id].toString(),
                    startedAt = row[JoggingSessions.startedAt].toString(),
                    endedAt = row[JoggingSessions.endedAt]?.toString(),
                    distanceMeters = row[JoggingSessions.distanceMeters].toDouble(),
                    durationSeconds = row[JoggingSessions.durationSeconds],
                    avgPaceSecondsPerKm = row[JoggingSessions.avgPaceSecondsPerKm],
                    caloriesBurned = row[JoggingSessions.caloriesBurned],
                    earnedTimeCredits = row[JoggingSessions.earnedTimeCredits],
                )
            }
    }

    /**
     * Returns the route points for a specific jogging session.
     */
    suspend fun getRoutePoints(sessionId: UUID, userId: UUID): List<RoutePointResponseDTO> = newSuspendedTransaction {
        // Verify the session belongs to the user
        val session = JoggingSessions
            .select(JoggingSessions.userId)
            .where { JoggingSessions.id eq sessionId }
            .firstOrNull()
            ?: return@newSuspendedTransaction emptyList()

        if (session[JoggingSessions.userId] != userId) {
            return@newSuspendedTransaction emptyList()
        }

        RoutePoints
            .select(
                RoutePoints.id,
                RoutePoints.timestamp,
                RoutePoints.latitude,
                RoutePoints.longitude,
                RoutePoints.altitude,
                RoutePoints.speed,
                RoutePoints.horizontalAccuracy,
                RoutePoints.distanceFromStart,
            )
            .where { RoutePoints.sessionId eq sessionId }
            .orderBy(RoutePoints.timestamp to SortOrder.ASC)
            .map { row ->
                RoutePointResponseDTO(
                    id = row[RoutePoints.id].toString(),
                    timestamp = row[RoutePoints.timestamp].toString(),
                    latitude = row[RoutePoints.latitude],
                    longitude = row[RoutePoints.longitude],
                    altitude = row[RoutePoints.altitude],
                    speed = row[RoutePoints.speed],
                    horizontalAccuracy = row[RoutePoints.horizontalAccuracy],
                    distanceFromStart = row[RoutePoints.distanceFromStart],
                )
            }
    }

    companion object {
        private fun emptyTotalStats() = JoggingTotalStatsDTO(
            totalDistanceMeters = 0.0,
            totalDurationSeconds = 0L,
            totalSessions = 0,
            totalCaloriesBurned = 0,
            totalEarnedSeconds = 0L,
            avgPaceSecondsPerKm = null,
            bestDistanceMeters = null,
        )
    }
}

// =============================================================================
// DTOs for jogging stats API responses
// =============================================================================

@kotlinx.serialization.Serializable
data class JoggingTotalStatsDTO(
    val totalDistanceMeters: Double,
    val totalDurationSeconds: Long,
    val totalSessions: Int,
    val totalCaloriesBurned: Int,
    val totalEarnedSeconds: Long,
    val avgPaceSecondsPerKm: Int?,
    val bestDistanceMeters: Double?,
)

@kotlinx.serialization.Serializable
data class JoggingSessionHistoryDTO(
    val id: String,
    val startedAt: String,
    val endedAt: String?,
    val distanceMeters: Double,
    val durationSeconds: Int,
    val avgPaceSecondsPerKm: Int?,
    val caloriesBurned: Int,
    val earnedTimeCredits: Int,
)

@kotlinx.serialization.Serializable
data class RoutePointResponseDTO(
    val id: String,
    val timestamp: String,
    val latitude: Double,
    val longitude: Double,
    val altitude: Float?,
    val speed: Float?,
    val horizontalAccuracy: Float?,
    val distanceFromStart: Float,
)
