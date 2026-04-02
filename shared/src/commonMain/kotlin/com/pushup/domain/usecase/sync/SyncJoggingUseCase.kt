package com.pushup.domain.usecase.sync

import com.pushup.data.api.ApiException
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.UpdateJoggingSessionRequest
import com.pushup.data.api.dto.toCreateRequest
import com.pushup.data.api.isTransient
import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.repository.JoggingSessionRepository
import com.pushup.domain.repository.JoggingSegmentRepository
import com.pushup.domain.repository.RoutePointRepository
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay

/**
 * Use-case: Upload all locally unsynced [JoggingSession]s and their route points to Supabase.
 *
 * Follows the same offline-first pattern as [SyncWorkoutsUseCase]:
 * - Sessions with [SyncStatus.PENDING] or [SyncStatus.FAILED] are eligible.
 * - In-progress sessions (endedAt == null) are skipped.
 * - Conflict resolution: "Last Write Wins" on [JoggingSession.startedAt].
 * - Retry with exponential back-off for transient errors.
 * - Route points are bulk-uploaded after the session is synced.
 *
 * @property sessionRepository   Local repository for jogging sessions.
 * @property routePointRepository Local repository for route points.
 * @property supabaseClient      Remote API client for Supabase PostgREST operations.
 * @property networkMonitor      Checks whether the device has internet connectivity.
 * @property maxRetries          Maximum retry attempts per session (default 3).
 * @property baseDelayMs         Base delay in milliseconds for exponential back-off (default 500).
 */
class SyncJoggingUseCase(
    private val sessionRepository: JoggingSessionRepository,
    private val segmentRepository: JoggingSegmentRepository,
    private val routePointRepository: RoutePointRepository,
    private val supabaseClient: CloudSyncApi,
    private val networkMonitor: NetworkMonitor,
    private val maxRetries: Int = 3,
    private val baseDelayMs: Long = 500L,
) {
    private val distanceEpsilonMeters = 1.0
    private val durationEpsilonSeconds = 2L


    /**
     * Uploads all unsynced jogging sessions for [userId] to Supabase.
     *
     * @param userId The ID of the user whose sessions to sync.
     * @return A [SyncJoggingResult] with counts of synced, skipped, and failed sessions.
     * @throws IllegalArgumentException if [userId] is blank.
     * @throws SyncException.NoNetwork if the device has no internet connection.
     */
    suspend operator fun invoke(userId: String): SyncJoggingResult {
        require(userId.isNotBlank()) { "userId must not be blank" }

        if (!networkMonitor.isConnected()) {
            throw SyncException.NoNetwork("Cannot sync jogging sessions: no internet connection")
        }

        val unsynced = sessionRepository.getUnsyncedSessions(userId)
        if (unsynced.isEmpty()) {
            return SyncJoggingResult(synced = 0, skipped = 0, failed = 0)
        }

        var synced = 0
        var skipped = 0
        var failed = 0

        for (session in unsynced) {
            if (session.endedAt == null) {
                skipped++
                continue
            }
            when (uploadWithRetry(session)) {
                UploadOutcome.SYNCED  -> synced++
                UploadOutcome.SKIPPED -> skipped++
                UploadOutcome.FAILED  -> failed++
            }
        }

        return SyncJoggingResult(synced = synced, skipped = skipped, failed = failed)
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private suspend fun uploadWithRetry(session: JoggingSession): UploadOutcome {
        var lastException: Exception? = null

        repeat(maxRetries) { attempt ->
            try {
                return doUpload(session)
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiException) {
                if (!e.isTransient) {
                    markFailed(session.id)
                    return UploadOutcome.FAILED
                }
                lastException = e
                delay(baseDelayMs * (1L shl attempt))
            } catch (e: Exception) {
                lastException = e
                delay(baseDelayMs * (1L shl attempt))
            }
        }

        markFailed(session.id)
        return UploadOutcome.FAILED
    }

    private suspend fun doUpload(session: JoggingSession): UploadOutcome {
        return try {
            supabaseClient.createJoggingSession(session.toCreateRequest())
            // Upload route points for this session
            uploadRoutePoints(session.id)
            uploadSegments(session.id)
            sessionRepository.markAsSynced(session.id)
            UploadOutcome.SYNCED
        } catch (e: ApiException.Conflict) {
            resolveConflict(session)
        }
    }

    /**
     * Uploads all route points for a session in a single bulk request.
     *
     * Uses `resolution=ignore-duplicates` on the server side, so points that
     * were already uploaded (e.g. by [LiveJoggingSessionManager]) are silently
     * skipped while new points are still inserted.
     */
    private suspend fun uploadRoutePoints(sessionId: String) {
        val routePoints = routePointRepository.getBySessionId(sessionId)
        if (routePoints.isEmpty()) return

        val requests = routePoints.map { it.toCreateRequest() }
        supabaseClient.createRoutePoints(requests)
    }

    private suspend fun uploadSegments(sessionId: String) {
        val segments = segmentRepository.getBySessionId(sessionId)
        val requests = segments.map { it.toCreateRequest() }
        supabaseClient.replaceJoggingSegments(sessionId, requests)
    }

    private suspend fun resolveConflict(local: JoggingSession): UploadOutcome {
        return try {
            val remote = supabaseClient.getJoggingSession(local.id)
            if (local.startedAt > remote.startedAt) {
                supabaseClient.updateJoggingSession(
                    id = local.id,
                    request = UpdateJoggingSessionRequest(
                        endedAt = local.endedAt?.toString(),
                        distanceMeters = local.distanceMeters.toFloat(),
                        durationSeconds = local.durationSeconds.toInt(),
                        avgPaceSecondsPerKm = local.avgPaceSecondsPerKm,
                        caloriesBurned = local.caloriesBurned,
                        earnedTimeCredits = local.earnedTimeCreditSeconds.toInt(),
                        activeDurationSeconds = local.activeDurationSeconds.toInt(),
                        pauseDurationSeconds = local.pauseDurationSeconds.toInt(),
                        activeDistanceMeters = local.activeDistanceMeters.toFloat(),
                        pauseDistanceMeters = local.pauseDistanceMeters.toFloat(),
                        pauseCount = local.pauseCount,
                    ),
                )
                uploadRoutePoints(local.id)
                uploadSegments(local.id)
                sessionRepository.markAsSynced(local.id)
                return UploadOutcome.SYNCED
            }

            // Session header already exists on server. Always upload route points
            // and segments -- the session may have been created by a background
            // upload that only sent the header without GPS data.
            uploadRoutePoints(local.id)
            uploadSegments(local.id)

            if (sessionsEffectivelyEqual(local, remote)) {
                sessionRepository.markAsSynced(local.id)
                UploadOutcome.SYNCED
            } else {
                // Session header on server has stale metrics (e.g. uploaded before
                // updateSegmentMetrics ran). Patch it with the correct local values.
                supabaseClient.updateJoggingSession(
                    id = local.id,
                    request = UpdateJoggingSessionRequest(
                        endedAt = local.endedAt?.toString(),
                        distanceMeters = local.distanceMeters.toFloat(),
                        durationSeconds = local.durationSeconds.toInt(),
                        avgPaceSecondsPerKm = local.avgPaceSecondsPerKm,
                        caloriesBurned = local.caloriesBurned,
                        earnedTimeCredits = local.earnedTimeCreditSeconds.toInt(),
                        activeDurationSeconds = local.activeDurationSeconds.toInt(),
                        pauseDurationSeconds = local.pauseDurationSeconds.toInt(),
                        activeDistanceMeters = local.activeDistanceMeters.toFloat(),
                        pauseDistanceMeters = local.pauseDistanceMeters.toFloat(),
                        pauseCount = local.pauseCount,
                    ),
                )
                sessionRepository.markAsSynced(local.id)
                UploadOutcome.SYNCED
            }
        } catch (e: ApiException) {
            if (e.isTransient) throw e
            markFailed(local.id)
            UploadOutcome.FAILED
        }
    }

    private suspend fun markFailed(sessionId: String) {
        try {
            val session = sessionRepository.getById(sessionId) ?: return
            sessionRepository.save(session.copy(syncStatus = SyncStatus.FAILED))
        } catch (_: Exception) {
            // Best-effort
        }
    }

    private fun sessionsEffectivelyEqual(local: JoggingSession, remote: JoggingSession): Boolean {
        return local.startedAt == remote.startedAt &&
            local.endedAt == remote.endedAt &&
            nearlyEqual(local.distanceMeters, remote.distanceMeters, distanceEpsilonMeters) &&
            nearlyEqual(local.activeDistanceMeters, remote.activeDistanceMeters, distanceEpsilonMeters) &&
            nearlyEqual(local.pauseDistanceMeters, remote.pauseDistanceMeters, distanceEpsilonMeters) &&
            nearlyEqual(local.durationSeconds, remote.durationSeconds, durationEpsilonSeconds) &&
            nearlyEqual(local.activeDurationSeconds, remote.activeDurationSeconds, durationEpsilonSeconds) &&
            nearlyEqual(local.pauseDurationSeconds, remote.pauseDurationSeconds, durationEpsilonSeconds) &&
            local.avgPaceSecondsPerKm == remote.avgPaceSecondsPerKm &&
            local.caloriesBurned == remote.caloriesBurned &&
            local.earnedTimeCreditSeconds == remote.earnedTimeCreditSeconds &&
            local.pauseCount == remote.pauseCount
    }

    private fun nearlyEqual(a: Double, b: Double, tolerance: Double): Boolean = kotlin.math.abs(a - b) <= tolerance

    private fun nearlyEqual(a: Long, b: Long, tolerance: Long): Boolean = kotlin.math.abs(a - b) <= tolerance

    private enum class UploadOutcome { SYNCED, SKIPPED, FAILED }
}

// =============================================================================
// Result type
// =============================================================================

/**
 * Summary of a [SyncJoggingUseCase] invocation.
 */
data class SyncJoggingResult(
    val synced: Int,
    val skipped: Int,
    val failed: Int,
) {
    val isFullSuccess: Boolean get() = failed == 0
}
