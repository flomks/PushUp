package com.sinura.domain.usecase

import com.sinura.domain.model.LiveRunParticipant
import com.sinura.domain.model.LiveRunSession
import com.sinura.domain.model.RunParticipantStatus
import com.sinura.domain.repository.LiveRunSessionRepository
import kotlinx.datetime.Clock

data class FinishLiveRunSessionResult(
    val participant: LiveRunParticipant,
    val session: LiveRunSession,
    val newLeaderUserId: String?,
)

class FinishLiveRunSessionUseCase(
    private val repository: LiveRunSessionRepository,
    private val clock: Clock = Clock.System,
) {
    suspend operator fun invoke(
        sessionId: String,
        userId: String,
    ): FinishLiveRunSessionResult {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }
        require(userId.isNotBlank()) { "userId must not be blank" }

        val session = repository.getById(sessionId)
            ?: error("Live run session not found: $sessionId")
        val participants = repository.getParticipants(sessionId)
        val participant = participants.firstOrNull { it.userId == userId }
            ?: error("Participant '$userId' not found in live run session '$sessionId'")

        val now = clock.now()
        val finishedParticipant = repository.upsertParticipant(
            participant.copy(
                status = RunParticipantStatus.FINISHED,
                finishedAt = now,
                isLeader = false,
                updatedAt = now,
            )
        )

        val refreshedParticipants = repository.getParticipants(sessionId)
            .map { if (it.userId == userId) finishedParticipant else it }
        val activeParticipants = refreshedParticipants.filter {
            it.status == RunParticipantStatus.ACTIVE ||
                it.status == RunParticipantStatus.JOINED ||
                it.status == RunParticipantStatus.PAUSED
        }

        val nextLeader = if (session.leaderUserId == userId) {
            LeaderSelectionPolicy.selectNextLeader(activeParticipants)
        } else {
            null
        }

        val stateUpdatedSession = repository.updateState(
            sessionId,
            LiveRunLifecyclePolicy.nextStateAfterFinish(session, activeParticipants),
        )

        val updatedSession = if (nextLeader != null) {
            repository.updateLeader(sessionId, nextLeader.userId)
        } else {
            stateUpdatedSession
        }

        return FinishLiveRunSessionResult(
            participant = finishedParticipant,
            session = updatedSession,
            newLeaderUserId = nextLeader?.userId,
        )
    }
}
