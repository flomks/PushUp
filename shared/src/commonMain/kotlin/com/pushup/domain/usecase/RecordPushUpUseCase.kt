package com.pushup.domain.usecase

import com.pushup.domain.model.PushUpRecord
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.PushUpRecordRepository
import com.pushup.domain.repository.WorkoutSessionRepository
import kotlinx.datetime.Clock

/**
 * Use-case: Record a single push-up repetition within an active workout session.
 *
 * When called, this use-case:
 * 1. Verifies the session exists and is still active ([WorkoutSession.endedAt] == `null`).
 * 2. Creates and persists a new [PushUpRecord] with the provided quality metrics.
 * 3. Updates the parent [WorkoutSession]: increments [WorkoutSession.pushUpCount] by 1
 *    and recalculates [WorkoutSession.quality] as a running average of all `formScore` values.
 *
 * @property sessionRepository Repository for reading and updating workout sessions.
 * @property recordRepository Repository for persisting push-up records.
 * @property clock Clock used to timestamp the new push-up record.
 * @property idGenerator Strategy for generating unique record IDs.
 */
class RecordPushUpUseCase(
    private val sessionRepository: WorkoutSessionRepository,
    private val recordRepository: PushUpRecordRepository,
    private val clock: Clock = Clock.System,
    private val idGenerator: IdGenerator = DefaultIdGenerator,
) {

    /**
     * Records a single push-up for the given session.
     *
     * @param sessionId The ID of the active workout session.
     * @param durationMs Time in milliseconds taken to complete this push-up (must be > 0).
     * @param depthScore How deep the push-up went (0.0 = shallow, 1.0 = full depth).
     * @param formScore Overall form quality (0.0 = poor, 1.0 = perfect).
     * @return The newly created [PushUpRecord].
     * @throws SessionNotFoundException if no session with [sessionId] exists.
     * @throws SessionAlreadyEndedException if the session has already been finished.
     */
    suspend operator fun invoke(
        sessionId: String,
        durationMs: Long,
        depthScore: Float,
        formScore: Float,
    ): PushUpRecord {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }

        val session = sessionRepository.getById(sessionId)
            ?: throw SessionNotFoundException("Session '$sessionId' not found")

        if (!session.isActive) {
            throw SessionAlreadyEndedException(
                "Session '$sessionId' has already ended at ${session.endedAt}",
            )
        }

        val record = PushUpRecord(
            id = idGenerator.generate(),
            sessionId = sessionId,
            timestamp = clock.now(),
            durationMs = durationMs,
            depthScore = depthScore,
            formScore = formScore,
        )
        recordRepository.save(record)

        // Recalculate running average quality incrementally.
        // Formula: newAvg = (oldAvg * oldCount + newFormScore) / (oldCount + 1)
        // Uses updateStats() (a targeted UPDATE) instead of save() (INSERT OR REPLACE)
        // to avoid triggering ON DELETE CASCADE on PushUpRecord child rows.
        val newCount = session.pushUpCount + 1
        val newQuality = ((session.quality * session.pushUpCount) + formScore) / newCount

        sessionRepository.updateStats(sessionId, newCount, newQuality)

        return record
    }
}

/**
 * Thrown when a referenced workout session does not exist.
 *
 * @param message A human-readable description of the missing session.
 */
class SessionNotFoundException(message: String) : IllegalArgumentException(message)

/**
 * Thrown when attempting to record a push-up in a session that has already ended.
 *
 * @param message A human-readable description of the conflict.
 */
class SessionAlreadyEndedException(message: String) : IllegalStateException(message)
