package com.pushup.domain.usecase

import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.repository.JoggingSessionRepository
import kotlinx.datetime.Clock

/**
 * Use-case: Start a new jogging session for a user.
 *
 * Creates a fresh [JoggingSession] with the current timestamp as startedAt,
 * all counters at zero, and PENDING sync status. The session is persisted
 * via [JoggingSessionRepository] and returned to the caller.
 *
 * If the user already has an active jogging session (endedAt == null), that
 * session is returned instead of creating a new one (idempotent).
 */
class StartJoggingUseCase(
    private val sessionRepository: JoggingSessionRepository,
    private val clock: Clock = Clock.System,
    private val idGenerator: IdGenerator = DefaultIdGenerator,
) {

    /**
     * Starts a new jogging session for the given [userId].
     *
     * @param userId The ID of the user starting the jog.
     * @return The newly created [JoggingSession], or the existing active session.
     */
    suspend operator fun invoke(userId: String): JoggingSession {
        require(userId.isNotBlank()) { "userId must not be blank" }

        val activeSessions = sessionRepository.getAllByUserId(userId)
            .filter { it.isActive }
        if (activeSessions.isNotEmpty()) {
            return activeSessions.first()
        }

        val now = clock.now()
        val session = JoggingSession(
            id = idGenerator.generate(),
            userId = userId,
            startedAt = now,
            endedAt = null,
            distanceMeters = 0.0,
            durationSeconds = 0L,
            avgPaceSecondsPerKm = null,
            caloriesBurned = 0,
            earnedTimeCreditSeconds = 0L,
            syncStatus = SyncStatus.PENDING,
        )
        sessionRepository.save(session)
        return session
    }
}
