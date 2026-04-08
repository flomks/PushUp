package com.pushup.domain.usecase.sync

import com.pushup.data.api.ApiException
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.UpdateJoggingSessionRequest
import com.pushup.data.api.dto.toCreateRequest
import com.pushup.data.api.isTransient
import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.repository.JoggingPlaybackEntryRepository
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
    private val playbackRepository: JoggingPlaybackEntryRepository? = null,
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

        println("[SyncJoggingUseCase] Starting jogging sync for userId=$userId")

        if (!networkMonitor.isConnected()) {
            println("[SyncJoggingUseCase] Aborting jogging sync: no network connection")
            throw SyncException.NoNetwork("Cannot sync jogging sessions: no internet connection")
        }

        val unsynced = sessionRepository.getUnsyncedSessions(userId)
        println("[SyncJoggingUseCase] Found ${unsynced.size} unsynced jogging session(s)")
        if (unsynced.isEmpty()) {
            return SyncJoggingResult(synced = 0, skipped = 0, failed = 0)
        }

        var synced = 0
        var skipped = 0
        var failed = 0

        for (session in unsynced) {
            if (session.endedAt == null) {
                println("[SyncJoggingUseCase] Skipping in-progress jogging session id=${session.id}")
                skipped++
                continue
            }
            println(
                "[SyncJoggingUseCase] Uploading session id=${session.id} " +
                    "liveRunSessionId=${session.liveRunSessionId} " +
                    "distanceMeters=${session.distanceMeters} durationSeconds=${session.durationSeconds}",
            )
            when (uploadWithRetry(session)) {
                UploadOutcome.SYNCED  -> synced++
                UploadOutcome.SKIPPED -> skipped++
                UploadOutcome.FAILED  -> failed++
            }
        }

        println("[SyncJoggingUseCase] Finished jogging sync: synced=$synced skipped=$skipped failed=$failed")
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
                    println("[SyncJoggingUseCase] Non-transient API error for session id=${session.id}: ${e.toLogMessage()}")
                    markFailed(session.id)
                    return UploadOutcome.FAILED
                }
                lastException = e
                println("[SyncJoggingUseCase] Transient API error for session id=${session.id}, retry=${attempt + 1}/${maxRetries}: ${e.toLogMessage()}")
                delay(baseDelayMs * (1L shl attempt))
            } catch (e: Exception) {
                lastException = e
                println("[SyncJoggingUseCase] Unexpected error for session id=${session.id}, retry=${attempt + 1}/${maxRetries}: ${e.message}")
                delay(baseDelayMs * (1L shl attempt))
            }
        }

        println("[SyncJoggingUseCase] Exhausted retries for session id=${session.id}: ${lastException?.message}")
        markFailed(session.id)
        return UploadOutcome.FAILED
    }

    private suspend fun doUpload(session: JoggingSession): UploadOutcome {
        return try {
            val normalizedSession = createSessionWithFallback(session)
            // Upload route points for this session
            uploadRoutePoints(normalizedSession.id)
            uploadSegments(normalizedSession.id)
            uploadPlaybackEntries(normalizedSession.id)
            sessionRepository.markAsSynced(normalizedSession.id)
            UploadOutcome.SYNCED
        } catch (e: ApiException.Conflict) {
            resolveConflict(session)
        }
    }

    private suspend fun createSessionWithFallback(session: JoggingSession): JoggingSession {
        return try {
            supabaseClient.createJoggingSession(session.toCreateRequest())
            println("[SyncJoggingUseCase] Created jogging session in cloud id=${session.id}")
            session
        } catch (e: ApiException) {
            if (!e.isMissingLiveRunReference() || session.liveRunSessionId == null) throw e
            println(
                "[SyncJoggingUseCase] Missing live_run_session reference for session id=${session.id}. " +
                    "Retrying without liveRunSessionId=${session.liveRunSessionId}",
            )
            val normalized = persistWithoutLiveRunReference(session)
            supabaseClient.createJoggingSession(normalized.toCreateRequest())
            println("[SyncJoggingUseCase] Created jogging session in cloud after fallback id=${session.id}")
            normalized
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
        println("[SyncJoggingUseCase] Uploaded ${requests.size} route point(s) for session id=$sessionId")
    }

    private suspend fun uploadSegments(sessionId: String) {
        val segments = segmentRepository.getBySessionId(sessionId)
        val requests = segments.map { it.toCreateRequest() }
        supabaseClient.replaceJoggingSegments(sessionId, requests)
        println("[SyncJoggingUseCase] Uploaded ${requests.size} segment(s) for session id=$sessionId")
    }

    private suspend fun uploadPlaybackEntries(sessionId: String) {
        val repository = playbackRepository ?: return
        val entries = repository.getBySessionId(sessionId)
        val requests = entries.map { it.toCreateRequest() }
        supabaseClient.replaceJoggingPlaybackEntries(sessionId, requests)
        println("[SyncJoggingUseCase] Uploaded ${requests.size} playback entrie(s) for session id=$sessionId")
    }

    private suspend fun resolveConflict(local: JoggingSession): UploadOutcome {
        return try {
            val remote = supabaseClient.getJoggingSession(local.id)
            val normalizedLocal = normalizeForMissingLiveRunReference(local, remote)
            if (normalizedLocal.startedAt > remote.startedAt) {
                println("[SyncJoggingUseCase] Conflict for session id=${local.id}: local is newer, patching remote")
                supabaseClient.updateJoggingSession(
                    id = normalizedLocal.id,
                    request = UpdateJoggingSessionRequest(
                        liveRunSessionId = normalizedLocal.liveRunSessionId,
                        endedAt = normalizedLocal.endedAt?.toString(),
                        distanceMeters = normalizedLocal.distanceMeters.toFloat(),
                        durationSeconds = normalizedLocal.durationSeconds.toInt(),
                        avgPaceSecondsPerKm = normalizedLocal.avgPaceSecondsPerKm,
                        caloriesBurned = normalizedLocal.caloriesBurned,
                        earnedTimeCredits = normalizedLocal.earnedTimeCreditSeconds.toInt(),
                        activeDurationSeconds = normalizedLocal.activeDurationSeconds.toInt(),
                        pauseDurationSeconds = normalizedLocal.pauseDurationSeconds.toInt(),
                        activeDistanceMeters = normalizedLocal.activeDistanceMeters.toFloat(),
                        pauseDistanceMeters = normalizedLocal.pauseDistanceMeters.toFloat(),
                        pauseCount = normalizedLocal.pauseCount,
                    ),
                )
                uploadRoutePoints(normalizedLocal.id)
                uploadSegments(normalizedLocal.id)
                uploadPlaybackEntries(normalizedLocal.id)
                sessionRepository.markAsSynced(normalizedLocal.id)
                return UploadOutcome.SYNCED
            }

            // Session header already exists on server. Always upload route points
            // and segments -- the session may have been created by a background
            // upload that only sent the header without GPS data.
            uploadRoutePoints(normalizedLocal.id)
            uploadSegments(normalizedLocal.id)
            uploadPlaybackEntries(normalizedLocal.id)

            if (sessionsEffectivelyEqual(normalizedLocal, remote)) {
                println("[SyncJoggingUseCase] Conflict for session id=${local.id}: local and remote effectively equal")
                sessionRepository.markAsSynced(normalizedLocal.id)
                UploadOutcome.SYNCED
            } else {
                // Session header on server has stale metrics (e.g. uploaded before
                // updateSegmentMetrics ran). Patch it with the correct local values.
                println("[SyncJoggingUseCase] Conflict for session id=${local.id}: patching stale remote metrics")
                supabaseClient.updateJoggingSession(
                    id = normalizedLocal.id,
                    request = UpdateJoggingSessionRequest(
                        liveRunSessionId = normalizedLocal.liveRunSessionId,
                        endedAt = normalizedLocal.endedAt?.toString(),
                        distanceMeters = normalizedLocal.distanceMeters.toFloat(),
                        durationSeconds = normalizedLocal.durationSeconds.toInt(),
                        avgPaceSecondsPerKm = normalizedLocal.avgPaceSecondsPerKm,
                        caloriesBurned = normalizedLocal.caloriesBurned,
                        earnedTimeCredits = normalizedLocal.earnedTimeCreditSeconds.toInt(),
                        activeDurationSeconds = normalizedLocal.activeDurationSeconds.toInt(),
                        pauseDurationSeconds = normalizedLocal.pauseDurationSeconds.toInt(),
                        activeDistanceMeters = normalizedLocal.activeDistanceMeters.toFloat(),
                        pauseDistanceMeters = normalizedLocal.pauseDistanceMeters.toFloat(),
                        pauseCount = normalizedLocal.pauseCount,
                    ),
                )
                sessionRepository.markAsSynced(normalizedLocal.id)
                UploadOutcome.SYNCED
            }
        } catch (e: ApiException) {
            if (e.isTransient) throw e
            println("[SyncJoggingUseCase] Conflict resolution failed for session id=${local.id}: ${e.toLogMessage()}")
            markFailed(local.id)
            UploadOutcome.FAILED
        }
    }

    private suspend fun normalizeForMissingLiveRunReference(
        local: JoggingSession,
        remote: JoggingSession,
    ): JoggingSession {
        if (local.liveRunSessionId == null || local.liveRunSessionId == remote.liveRunSessionId) {
            return local
        }
        return if (remote.liveRunSessionId == null) {
            persistWithoutLiveRunReference(local)
        } else {
            local
        }
    }

    private suspend fun persistWithoutLiveRunReference(session: JoggingSession): JoggingSession {
        val normalized = session.copy(liveRunSessionId = null, syncStatus = SyncStatus.PENDING)
        sessionRepository.save(normalized)
        println("[SyncJoggingUseCase] Cleared stale liveRunSessionId locally for session id=${session.id}")
        return normalized
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
            local.liveRunSessionId == remote.liveRunSessionId &&
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

    private fun ApiException.isMissingLiveRunReference(): Boolean {
        val message = (this.message ?: "").lowercase()
        return "live_run_session_id" in message ||
            "jogging_sessions_live_run_session_id_fkey" in message ||
            ("foreign key" in message && "live_run" in message)
    }

    private fun ApiException.toLogMessage(): String =
        when (this) {
            is ApiException.BadRequest -> serverMessage ?: message ?: "Bad request"
            is ApiException.ServerError -> serverMessage ?: message ?: "Server error"
            else -> message ?: this::class.simpleName ?: "ApiException"
        }

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
