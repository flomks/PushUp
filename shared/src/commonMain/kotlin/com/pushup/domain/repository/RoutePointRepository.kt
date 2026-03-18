package com.pushup.domain.repository

import com.pushup.domain.model.RoutePoint

/**
 * Repository for managing [RoutePoint] entities.
 *
 * Route points are GPS breadcrumbs recorded during a jogging session.
 *
 * Implementations must be **main-safe** -- all dispatcher switching is handled internally.
 */
interface RoutePointRepository {

    /** Persists a new route point. Throws if a point with the same ID already exists. */
    suspend fun save(routePoint: RoutePoint)

    /**
     * Persists a route point if no point with the same ID exists.
     * Silently ignores duplicates (INSERT OR IGNORE).
     * Useful for idempotent cloud-sync downloads.
     */
    suspend fun saveIfAbsent(routePoint: RoutePoint)

    /** Retrieves a route point by its unique [id]. */
    suspend fun getById(id: String): RoutePoint?

    /** Retrieves all route points for a session, ordered by timestamp ascending. */
    suspend fun getBySessionId(sessionId: String): List<RoutePoint>

    /** Returns the number of route points for a session. */
    suspend fun countBySessionId(sessionId: String): Long

    /** Deletes all route points for a session. */
    suspend fun deleteBySessionId(sessionId: String)
}
