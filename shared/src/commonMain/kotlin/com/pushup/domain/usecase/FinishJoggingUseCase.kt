package com.pushup.domain.usecase

import com.pushup.domain.model.ExerciseType
import com.pushup.domain.model.JoggingSummary
import com.pushup.domain.model.JoggingSegmentType
import com.pushup.domain.model.LevelCalculator
import com.pushup.domain.repository.ExerciseLevelRepository
import com.pushup.domain.repository.JoggingSegmentRepository
import com.pushup.domain.repository.JoggingSessionRepository
import com.pushup.domain.repository.LevelRepository
import com.pushup.domain.repository.RoutePointRepository
import com.pushup.domain.repository.TimeCreditRepository
import com.pushup.domain.repository.UserSettingsRepository
import kotlinx.datetime.Clock

/**
 * Use-case: Finish an active jogging session and calculate earned time credits.
 *
 * When invoked, this use-case:
 * 1. Verifies the session exists and is still active.
 * 2. Calculates earned credits based on distance and duration.
 *    Formula: 1 minute of screen time per 1 km jogged (minimum 1 minute for any distance > 100m).
 * 3. Persists the finished session and adds the earned seconds to TimeCreditRepository.
 * 4. Awards XP based on distance.
 * 5. Returns a [JoggingSummary] containing the finished session, route points, and credits.
 */
class FinishJoggingUseCase(
    private val sessionRepository: JoggingSessionRepository,
    private val segmentRepository: JoggingSegmentRepository,
    private val routePointRepository: RoutePointRepository,
    private val timeCreditRepository: TimeCreditRepository,
    private val settingsRepository: UserSettingsRepository,
    private val levelRepository: LevelRepository? = null,
    private val exerciseLevelRepository: ExerciseLevelRepository? = null,
    private val clock: Clock = Clock.System,
) {

    /**
     * Finishes the jogging session identified by [sessionId].
     *
     * @param sessionId The ID of the active session to finish.
     * @return A [JoggingSummary] with the completed session, route points, and earned credits.
     */
    suspend operator fun invoke(sessionId: String): JoggingSummary {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }

        val session = sessionRepository.getById(sessionId)
            ?: throw SessionNotFoundException("Jogging session '$sessionId' not found")

        if (!session.isActive) {
            throw SessionAlreadyEndedException(
                "Jogging session '$sessionId' has already ended at ${session.endedAt}",
            )
        }

        val now = clock.now()
        val wallDurationSeconds = (now - session.startedAt).inWholeSeconds
        val distanceMeters = session.distanceMeters

        val segments = segmentRepository.getBySessionId(sessionId)
        val activeDuration = segments
            .filter { it.type == JoggingSegmentType.RUN }
            .sumOf { it.durationSeconds }
        val pauseDuration = segments
            .filter { it.type == JoggingSegmentType.PAUSE }
            .sumOf { it.durationSeconds }
        val activeDistance = segments
            .filter { it.type == JoggingSegmentType.RUN }
            .sumOf { it.distanceMeters }
        val pauseDistance = segments
            .filter { it.type == JoggingSegmentType.PAUSE }
            .sumOf { it.distanceMeters }
        val pauseCount = segments.count { it.type == JoggingSegmentType.PAUSE }

        // Use active duration whenever segment data is available so pause time does
        // not dilute pace and other workout statistics.
        val durationSeconds = if (activeDuration > 0L) activeDuration else wallDurationSeconds

        // Calculate pace
        val avgPace = if (distanceMeters >= 100.0) {
            ((durationSeconds.toDouble() / distanceMeters) * 1000.0).toInt()
        } else {
            null
        }

        val caloriesBurned = (distanceMeters / 1000.0 * 60.0).toInt()

        // Credit formula: 1 minute (60 seconds) per 1 km jogged
        // Minimum 1 minute for any distance > 100m
        val earnedCredits: Long = if (distanceMeters >= 100.0) {
            val kmCredits = (distanceMeters / 1000.0 * 60.0).toLong()
            kmCredits.coerceAtLeast(60L) // minimum 1 minute
        } else {
            0L
        }

        // Finish the session
        sessionRepository.finishSession(
            id = sessionId,
            endedAt = now,
            distanceMeters = distanceMeters,
            durationSeconds = durationSeconds,
            avgPaceSecondsPerKm = avgPace,
            caloriesBurned = caloriesBurned,
            earnedTimeCreditSeconds = earnedCredits,
        )

        sessionRepository.updateSegmentMetrics(
            id = sessionId,
            activeDurationSeconds = activeDuration,
            pauseDurationSeconds = pauseDuration,
            activeDistanceMeters = activeDistance,
            pauseDistanceMeters = pauseDistance,
            pauseCount = pauseCount,
        )

        if (earnedCredits > 0) {
            timeCreditRepository.addEarnedSeconds(session.userId, earnedCredits)
        }

        // Award XP to the jogging activity itself. Account-wide XP is derived
        // from the sum of all activity-specific XP totals.
        val distanceUnits = (distanceMeters / 100.0).toInt()
        val earnedXp = LevelCalculator.calculateExerciseXp(
            exerciseType = ExerciseType.JOGGING,
            amount = distanceUnits,
        )
        if (earnedXp > 0) {
            exerciseLevelRepository?.addXp(session.userId, ExerciseType.JOGGING, earnedXp)
        }
        val updatedLevel = levelRepository?.getOrCreate(session.userId)

        val routePoints = routePointRepository.getBySessionId(sessionId)
        val finishedSession = sessionRepository.getById(sessionId)
            ?: error("Jogging session '$sessionId' disappeared after finishSession()")

        return JoggingSummary(
            session = finishedSession,
            routePoints = routePoints,
            earnedCredits = earnedCredits,
            earnedXp = earnedXp,
            updatedLevel = updatedLevel,
        )
    }
}
