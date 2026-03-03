package com.pushup.domain.usecase

import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.WorkoutSessionRepository
import kotlinx.datetime.Clock

/**
 * Use-case: Start a new workout session for a user.
 *
 * Creates a fresh [WorkoutSession] with the current timestamp as [WorkoutSession.startedAt],
 * all counters at zero, and [SyncStatus.PENDING] sync status. The session is persisted
 * via [WorkoutSessionRepository] and returned to the caller.
 *
 * Throws [WorkoutAlreadyActiveException] if the user already has an active session
 * (i.e. a session with [WorkoutSession.endedAt] == `null`).
 *
 * @property sessionRepository Repository used to persist and query workout sessions.
 * @property clock Clock used to generate the session start timestamp.
 * @property idGenerator Strategy for generating unique session IDs.
 */
class StartWorkoutUseCase(
    private val sessionRepository: WorkoutSessionRepository,
    private val clock: Clock = Clock.System,
    private val idGenerator: IdGenerator = DefaultIdGenerator,
) {

    /**
     * Starts a new workout session for the given [userId].
     *
     * @param userId The ID of the user starting the workout.
     * @return The newly created and persisted [WorkoutSession].
     * @throws WorkoutAlreadyActiveException if an active session already exists for this user.
     */
    suspend operator fun invoke(userId: String): WorkoutSession {
        require(userId.isNotBlank()) { "userId must not be blank" }

        val activeSessions = sessionRepository.getAllByUserId(userId)
            .filter { it.isActive }
        if (activeSessions.isNotEmpty()) {
            throw WorkoutAlreadyActiveException(
                "User '$userId' already has an active workout session: ${activeSessions.first().id}",
            )
        }

        val now = clock.now()
        val session = WorkoutSession(
            id = idGenerator.generate(),
            userId = userId,
            startedAt = now,
            endedAt = null,
            pushUpCount = 0,
            earnedTimeCreditSeconds = 0L,
            quality = 0.0f,
            syncStatus = SyncStatus.PENDING,
        )
        sessionRepository.save(session)
        return session
    }
}

/**
 * Thrown when attempting to start a workout while one is already active.
 *
 * @param message A human-readable description of the conflict.
 */
class WorkoutAlreadyActiveException(message: String) : IllegalStateException(message)
