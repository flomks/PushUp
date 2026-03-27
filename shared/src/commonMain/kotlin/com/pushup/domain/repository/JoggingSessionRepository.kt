package com.pushup.domain.repository

import com.pushup.domain.model.JoggingSession
import kotlinx.coroutines.flow.Flow
import kotlinx.datetime.Instant

/**
 * Repository for managing [JoggingSession] entities.
 *
 * Handles persistence and retrieval of jogging sessions, including
 * date-range queries and synchronization-status management.
 *
 * Implementations must be **main-safe** -- all dispatcher switching is handled internally.
 */
interface JoggingSessionRepository {

    /** Persists a new or updated [session] to the data store. */
    suspend fun save(session: JoggingSession)

    /** Retrieves a jogging session by its unique [id]. */
    suspend fun getById(id: String): JoggingSession?

    /** Retrieves all jogging sessions for [userId], ordered by startedAt descending. */
    suspend fun getAllByUserId(userId: String): List<JoggingSession>

    /** Retrieves jogging sessions for a user within a date range (inclusive). */
    suspend fun getByDateRange(userId: String, from: Instant, to: Instant): List<JoggingSession>

    /** Retrieves all sessions that have not yet been synced with the backend. */
    suspend fun getUnsyncedSessions(userId: String): List<JoggingSession>

    /**
     * Updates the running stats of an active jogging session.
     * Used during a jog to update distance, duration, pace, and calories in real-time.
     */
    suspend fun updateStats(
        id: String,
        distanceMeters: Double,
        durationSeconds: Long,
        avgPaceSecondsPerKm: Int?,
        caloriesBurned: Int,
    )

    /**
     * Marks the session as finished by setting endedAt and final stats.
     */
    suspend fun finishSession(
        id: String,
        endedAt: Instant,
        distanceMeters: Double,
        durationSeconds: Long,
        avgPaceSecondsPerKm: Int?,
        caloriesBurned: Int,
        earnedTimeCreditSeconds: Long,
    )

    /**
     * Persists derived pause/run aggregate metrics for an existing jogging session.
     */
    suspend fun updateSegmentMetrics(
        id: String,
        activeDurationSeconds: Long,
        pauseDurationSeconds: Long,
        activeDistanceMeters: Double,
        pauseDistanceMeters: Double,
        pauseCount: Int,
    )

    /** Marks the session as successfully synced with the backend. */
    suspend fun markAsSynced(id: String)

    /** Deletes the session with the given [id]. */
    suspend fun delete(id: String)

    /** Observes all jogging sessions for [userId] as a reactive Flow. */
    fun observeAllByUserId(userId: String): Flow<List<JoggingSession>>
}
