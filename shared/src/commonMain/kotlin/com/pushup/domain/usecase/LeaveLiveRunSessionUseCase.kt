package com.pushup.domain.usecase

import com.pushup.domain.model.LiveRunParticipant
import com.pushup.domain.model.RunParticipantStatus
import com.pushup.domain.repository.LiveRunSessionRepository
import kotlinx.datetime.Clock

class LeaveLiveRunSessionUseCase(
    private val repository: LiveRunSessionRepository,
    private val clock: Clock = Clock.System,
) {
    suspend operator fun invoke(
        sessionId: String,
        userId: String,
    ): LiveRunParticipant {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }
        require(userId.isNotBlank()) { "userId must not be blank" }

        val existing = repository.getParticipants(sessionId).firstOrNull { it.userId == userId }
            ?: error("Participant '$userId' not found in live run session '$sessionId'")

        val now = clock.now()
        return repository.upsertParticipant(
            existing.copy(
                status = RunParticipantStatus.LEFT,
                leftAt = now,
                isLeader = false,
                updatedAt = now,
            )
        )
    }
}
