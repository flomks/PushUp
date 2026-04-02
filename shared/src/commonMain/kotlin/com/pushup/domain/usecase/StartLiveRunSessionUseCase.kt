package com.pushup.domain.usecase

import com.pushup.domain.model.LiveRunParticipant
import com.pushup.domain.model.LiveRunSession
import com.pushup.domain.model.LiveRunSessionState
import com.pushup.domain.model.LiveRunSourceType
import com.pushup.domain.model.RunMode
import com.pushup.domain.model.RunParticipantStatus
import com.pushup.domain.model.RunVisibility
import com.pushup.domain.repository.LiveRunSessionRepository
import kotlinx.datetime.Clock

class StartLiveRunSessionUseCase(
    private val repository: LiveRunSessionRepository,
    private val clock: Clock = Clock.System,
    private val idGenerator: IdGenerator = DefaultIdGenerator,
) {
    suspend operator fun invoke(
        leaderUserId: String,
        mode: RunMode,
        visibility: RunVisibility,
        linkedEventId: String? = null,
    ): LiveRunSession {
        require(leaderUserId.isNotBlank()) { "leaderUserId must not be blank" }

        val now = clock.now()
        val session = LiveRunSession(
            id = idGenerator.generate(),
            sourceType = if (linkedEventId == null) LiveRunSourceType.SPONTANEOUS else LiveRunSourceType.PLANNED,
            linkedEventId = linkedEventId,
            leaderUserId = leaderUserId,
            visibility = visibility,
            mode = mode,
            state = LiveRunSessionState.LIVE,
            startedAt = now,
            cooldownStartedAt = null,
            endedAt = null,
            lastActivityAt = now,
            maxEndsAt = LiveRunLifecyclePolicy.initialMaxEndAt(now),
            createdAt = now,
            updatedAt = now,
        )
        val leader = LiveRunParticipant(
            id = idGenerator.generate(),
            sessionId = session.id,
            userId = leaderUserId,
            status = RunParticipantStatus.ACTIVE,
            joinedAt = now,
            becameActiveAt = now,
            finishedAt = null,
            leftAt = null,
            isLeader = true,
            createdAt = now,
            updatedAt = now,
        )

        return repository.create(session, leader)
    }
}
