package com.pushup.data.repository

import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.RoutePoint
import com.pushup.domain.repository.RoutePointRepository
import kotlinx.coroutines.CoroutineDispatcher

/**
 * SQLDelight-backed implementation of [RoutePointRepository].
 */
class RoutePointRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
) : RoutePointRepository {

    private val queries get() = database.databaseQueries

    override suspend fun save(routePoint: RoutePoint): Unit = safeDbCall(
        dispatcher,
        "Failed to save route point '${routePoint.id}'",
    ) {
        queries.insertRoutePoint(
            id = routePoint.id,
            sessionId = routePoint.sessionId,
            timestamp = routePoint.timestamp.toEpochMilliseconds(),
            latitude = routePoint.latitude,
            longitude = routePoint.longitude,
            altitude = routePoint.altitude,
            speed = routePoint.speed,
            horizontalAccuracy = routePoint.horizontalAccuracy,
            distanceFromStart = routePoint.distanceFromStart,
        )
    }

    override suspend fun saveIfAbsent(routePoint: RoutePoint): Unit = safeDbCall(
        dispatcher,
        "Failed to save-if-absent route point '${routePoint.id}'",
    ) {
        queries.insertOrIgnoreRoutePoint(
            id = routePoint.id,
            sessionId = routePoint.sessionId,
            timestamp = routePoint.timestamp.toEpochMilliseconds(),
            latitude = routePoint.latitude,
            longitude = routePoint.longitude,
            altitude = routePoint.altitude,
            speed = routePoint.speed,
            horizontalAccuracy = routePoint.horizontalAccuracy,
            distanceFromStart = routePoint.distanceFromStart,
        )
    }

    override suspend fun getById(id: String): RoutePoint? = safeDbCall(
        dispatcher,
        "Failed to get route point '$id'",
    ) {
        queries.selectRoutePointById(id).executeAsOneOrNull()?.toDomain()
    }

    override suspend fun getBySessionId(sessionId: String): List<RoutePoint> = safeDbCall(
        dispatcher,
        "Failed to get route points for session '$sessionId'",
    ) {
        queries.selectRoutePointsBySessionId(sessionId).executeAsList().map { it.toDomain() }
    }

    override suspend fun countBySessionId(sessionId: String): Long = safeDbCall(
        dispatcher,
        "Failed to count route points for session '$sessionId'",
    ) {
        queries.countRoutePointsBySessionId(sessionId).executeAsOne()
    }

    override suspend fun deleteBySessionId(sessionId: String): Unit = safeDbCall(
        dispatcher,
        "Failed to delete route points for session '$sessionId'",
    ) {
        queries.deleteRoutePointsBySessionId(sessionId)
    }
}
