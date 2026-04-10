package com.sinura.domain.usecase

import com.sinura.domain.model.SyncStatus
import com.sinura.domain.model.WorkoutSession
import com.sinura.domain.repository.WorkoutSessionRepository
import kotlinx.datetime.Clock

/**
 * Use-case: Start a new workout session for a user.
 *
 * Creates a fresh [WorkoutSession] with the current timestamp as [WorkoutSession.startedAt],
 * all counters at zero, and [SyncStatus.PENDING] sync status. The session is persisted
 * via [WorkoutSessionRepository] and returned to the caller.
 *
 * If the user already has an active session (endedAt == null), that session is returned
 * instead of creating a new one. This makes the use-case idempotent and prevents crashes
 * caused by dangling sessions left open after an app crash or force-quit.
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
     * If the user already has an active session (i.e. a session with
     * [WorkoutSession.endedAt] == `null`), that existing session is returned
     * instead of creating a new one. This makes the use-case idempotent and
     * prevents [WorkoutAlreadyActiveException] from crashing the iOS app when
     * the previous session was not cleanly finished (e.g. due to a crash or
     * force-quit before [FinishWorkoutUseCase] could run).
     *
     * @param userId The ID of the user starting the workout.
     * @return The newly created [WorkoutSession], or the existing active session
     *         if one is already open for this user.
     */
    suspend operator fun invoke(userId: String): WorkoutSession {
        require(userId.isNotBlank()) { "userId must not be blank" }

        val activeSessions = sessionRepository.getAllByUserId(userId)
            .filter { it.isActive }
        if (activeSessions.isNotEmpty()) {
            // Return the existing active session instead of throwing.
            // This handles the case where the app crashed or was force-quit
            // before the previous session was finished, leaving a dangling
            // open session in the local database.
            return activeSessions.first()
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
