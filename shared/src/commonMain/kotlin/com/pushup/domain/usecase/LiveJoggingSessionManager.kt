package com.pushup.domain.usecase

import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.UpsertLiveJoggingStatusRequest
import com.pushup.domain.model.RoutePoint
import com.pushup.domain.repository.RoutePointRepository
import com.pushup.domain.usecase.sync.NetworkMonitor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/**
 * Manages live data streaming during an active jogging session.
 *
 * ## Responsibilities
 * 1. **Live presence**: Periodically upserts the user's live jogging status
 *    to Supabase so friends can see they are running. Cleaned up on stop.
 * 2. **Batched route point upload**: Collects GPS route points in a local
 *    buffer and uploads them in batches to reduce network overhead. Points
 *    are always saved locally first (offline-first), then uploaded when
 *    connectivity is available.
 * 3. **Offline resilience**: If the network is unavailable, points accumulate
 *    locally and are uploaded by [SyncJoggingUseCase] after the session ends.
 *
 * ## Design for future Live Sharing
 * The live status table (`live_jogging_status`) is designed for Supabase
 * Realtime subscriptions. Friends can subscribe to changes on this table
 * filtered by user IDs they follow. The batched route point uploads ensure
 * that a live viewer can poll or subscribe for new route points as they
 * appear on the server.
 *
 * ## Efficiency
 * - Route points are uploaded in batches of [batchSize] or every
 *   [flushIntervalMs] milliseconds, whichever comes first.
 * - Live status is updated every [statusUpdateIntervalMs] milliseconds.
 * - All network calls are fire-and-forget with error swallowing -- a failed
 *   upload does not affect the local tracking experience.
 *
 * @property cloudSyncApi       Remote API for Supabase operations.
 * @property routePointRepository Local repository for route points.
 * @property networkMonitor     Checks connectivity before network calls.
 * @property clock              Clock for timestamps.
 * @property batchSize          Max route points per upload batch (default 10).
 * @property flushIntervalMs    Max time between batch uploads in ms (default 30_000).
 * @property statusUpdateIntervalMs Interval for live status heartbeats in ms (default 15_000).
 */
class LiveJoggingSessionManager(
    private val cloudSyncApi: CloudSyncApi,
    private val routePointRepository: RoutePointRepository,
    private val networkMonitor: NetworkMonitor,
    private val clock: Clock = Clock.System,
    private val batchSize: Int = 10,
    private val flushIntervalMs: Long = 30_000L,
    private val statusUpdateIntervalMs: Long = 15_000L,
) {

    private val scope = CoroutineScope(SupervisorJob())
    private val bufferMutex = Mutex()
    private val pendingPoints = mutableListOf<RoutePoint>()

    private var flushJob: Job? = null
    private var statusJob: Job? = null
    private var activeUserId: String? = null
    private var activeSessionId: String? = null
    private var sessionStartedAt: Instant? = null
    private var lastLatitude: Double? = null
    private var lastLongitude: Double? = null
    private var lastDistanceMeters: Double = 0.0
    private var lastDurationSeconds: Long = 0

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Starts live tracking for a jogging session.
     *
     * Immediately publishes the live status to Supabase (best-effort) and
     * starts the periodic flush and status update loops.
     */
    fun start(userId: String, sessionId: String, startedAt: Instant) {
        activeUserId = userId
        activeSessionId = sessionId
        sessionStartedAt = startedAt

        // Immediately publish live status
        scope.launch { publishLiveStatus() }

        // Start periodic flush loop
        flushJob?.cancel()
        flushJob = scope.launch {
            while (isActive) {
                delay(flushIntervalMs)
                flushBuffer()
            }
        }

        // Start periodic status heartbeat
        statusJob?.cancel()
        statusJob = scope.launch {
            while (isActive) {
                delay(statusUpdateIntervalMs)
                publishLiveStatus()
            }
        }
    }

    /**
     * Enqueues a route point for batched upload.
     *
     * The point is saved locally first (via the caller's [RecordRoutePointUseCase]),
     * then added to the upload buffer. When the buffer reaches [batchSize],
     * it is flushed to the server immediately.
     */
    fun enqueueRoutePoint(point: RoutePoint) {
        lastLatitude = point.latitude
        lastLongitude = point.longitude
        lastDistanceMeters = point.distanceFromStart
        val startedAt = sessionStartedAt
        if (startedAt != null) {
            lastDurationSeconds = (point.timestamp - startedAt).inWholeSeconds
        }

        scope.launch {
            bufferMutex.withLock {
                pendingPoints.add(point)
                if (pendingPoints.size >= batchSize) {
                    val batch = pendingPoints.toList()
                    pendingPoints.clear()
                    uploadBatch(batch)
                }
            }
        }
    }

    /**
     * Stops live tracking: flushes remaining points, removes live status.
     *
     * Call this when the jogging session ends. Any remaining buffered points
     * are uploaded, and the live status is deleted from Supabase.
     */
    fun stop() {
        flushJob?.cancel()
        flushJob = null
        statusJob?.cancel()
        statusJob = null

        scope.launch {
            // Final flush
            flushBuffer()
            // Remove live status
            removeLiveStatus()
            // Reset state
            activeUserId = null
            activeSessionId = null
            sessionStartedAt = null
            lastLatitude = null
            lastLongitude = null
            lastDistanceMeters = 0.0
            lastDurationSeconds = 0
        }
    }

    // =========================================================================
    // Private: Batch upload
    // =========================================================================

    private suspend fun flushBuffer() {
        val batch = bufferMutex.withLock {
            if (pendingPoints.isEmpty()) return
            val copy = pendingPoints.toList()
            pendingPoints.clear()
            copy
        }
        uploadBatch(batch)
    }

    private suspend fun uploadBatch(batch: List<RoutePoint>) {
        if (batch.isEmpty()) return
        try {
            if (!networkMonitor.isConnected()) return
            val requests = batch.map { it.toCreateRequest() }
            cloudSyncApi.createRoutePoints(requests)
        } catch (_: Exception) {
            // Non-fatal: points are already saved locally and will be
            // uploaded by SyncJoggingUseCase after the session ends.
        }
    }

    private fun RoutePoint.toCreateRequest() =
        com.pushup.data.api.dto.CreateRoutePointRequest(
            id = id,
            sessionId = sessionId,
            timestamp = timestamp.toString(),
            latitude = latitude,
            longitude = longitude,
            altitude = altitude?.toFloat(),
            speed = speed?.toFloat(),
            horizontalAccuracy = horizontalAccuracy?.toFloat(),
            distanceFromStart = distanceFromStart.toFloat(),
        )

    // =========================================================================
    // Private: Live status
    // =========================================================================

    private suspend fun publishLiveStatus() {
        val userId = activeUserId ?: return
        val sessionId = activeSessionId ?: return
        val startedAt = sessionStartedAt ?: return

        try {
            if (!networkMonitor.isConnected()) return
            cloudSyncApi.upsertLiveJoggingStatus(
                UpsertLiveJoggingStatusRequest(
                    userId = userId,
                    sessionId = sessionId,
                    startedAt = startedAt.toString(),
                    lastLatitude = lastLatitude,
                    lastLongitude = lastLongitude,
                    lastDistanceMeters = lastDistanceMeters.toFloat(),
                    lastDurationSeconds = lastDurationSeconds.toInt(),
                    lastUpdatedAt = clock.now().toString(),
                ),
            )
        } catch (_: Exception) {
            // Best-effort: live status is ephemeral
        }
    }

    private suspend fun removeLiveStatus() {
        val userId = activeUserId ?: return
        try {
            if (!networkMonitor.isConnected()) return
            cloudSyncApi.deleteLiveJoggingStatus(userId)
        } catch (_: Exception) {
            // Best-effort: stale status will be cleaned up by TTL or next login
        }
    }
}
