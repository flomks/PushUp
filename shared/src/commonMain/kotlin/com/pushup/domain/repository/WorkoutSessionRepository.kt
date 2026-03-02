package com.pushup.domain.repository

import com.pushup.domain.model.WorkoutSession
import kotlinx.coroutines.flow.Flow
import kotlinx.datetime.Instant

/**
 * Repository for managing [WorkoutSession] entities.
 *
 * Handles persistence and retrieval of workout sessions, including
 * date-range queries and synchronization-status management.
 */
interface WorkoutSessionRepository {

    /**
     * Persists a new or updated [session] to the data store.
     *
     * @param session The workout session to save.
     */
    suspend fun save(session: WorkoutSession)

    /**
     * Retrieves a workout session by its unique [id].
     *
     * @param id The unique identifier of the session.
     * @return The matching session, or `null` if not found.
     */
    suspend fun getById(id: String): WorkoutSession?

    /**
     * Retrieves all workout sessions belonging to the given [userId],
     * ordered by [WorkoutSession.startedAt] descending (most recent first).
     *
     * @param userId The user whose sessions to retrieve.
     * @return A list of all sessions for the user, possibly empty.
     */
    suspend fun getAllByUserId(userId: String): List<WorkoutSession>

    /**
     * Retrieves all workout sessions for a user that started within the given time range.
     *
     * @param userId The user whose sessions to retrieve.
     * @param from Start of the time range (inclusive).
     * @param to End of the time range (inclusive).
     * @return Sessions whose [WorkoutSession.startedAt] falls within `[from, to]`.
     */
    suspend fun getByDateRange(userId: String, from: Instant, to: Instant): List<WorkoutSession>

    /**
     * Retrieves all sessions for a user that have not yet been synchronized with the backend.
     *
     * @param userId The user whose unsynced sessions to retrieve.
     * @return Sessions with a non-[com.pushup.domain.model.SyncStatus.SYNCED] status.
     */
    suspend fun getUnsyncedSessions(userId: String): List<WorkoutSession>

    /**
     * Marks the session with the given [id] as successfully synced with the backend.
     *
     * @param id The unique identifier of the session to mark.
     */
    suspend fun markAsSynced(id: String)

    /**
     * Deletes the session with the given [id] from the data store.
     *
     * @param id The unique identifier of the session to delete.
     */
    suspend fun delete(id: String)

    /**
     * Observes all workout sessions for the given [userId] as a reactive [Flow].
     *
     * @param userId The user whose sessions to observe.
     */
    fun observeAllByUserId(userId: String): Flow<List<WorkoutSession>>
}
