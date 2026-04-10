package com.sinura.domain.usecase

import com.sinura.domain.model.LiveRunParticipant
import com.sinura.domain.model.LiveRunSessionState
import com.sinura.domain.model.RunParticipantStatus
import com.sinura.domain.repository.LiveRunSessionRepository
import kotlinx.datetime.Clock

class JoinLiveRunSessionUseCase(
    private val repository: LiveRunSessionRepository,
    private val clock: Clock = Clock.System,
    private val idGenerator: IdGenerator = DefaultIdGenerator,
) {
    suspend operator fun invoke(
        sessionId: String,
        userId: String,
    ): LiveRunParticipant {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }
        require(userId.isNotBlank()) { "userId must not be blank" }

        val session = repository.getById(sessionId)
            ?: error("Live run session not found: $sessionId")
        require(session.state != LiveRunSessionState.FINISHED) {
            "Cannot join finished live run session '$sessionId'"
        }

        val now = clock.now()
        if (session.state == LiveRunSessionState.COOLDOWN) {
            repository.updateState(sessionId, LiveRunSessionState.LIVE)
        }

        val existing = repository.getParticipants(sessionId).firstOrNull { it.userId == userId }
        val participant = existing?.copy(
            status = RunParticipantStatus.ACTIVE,
            becameActiveAt = existing.becameActiveAt ?: now,
            finishedAt = null,
            leftAt = null,
            updatedAt = now,
        ) ?: LiveRunParticipant(
            id = idGenerator.generate(),
            sessionId = sessionId,
            userId = userId,
            status = RunParticipantStatus.ACTIVE,
            joinedAt = now,
            becameActiveAt = now,
            finishedAt = null,
            leftAt = null,
            isLeader = false,
            createdAt = now,
            updatedAt = now,
        )

        return repository.upsertParticipant(participant)
    }
}
