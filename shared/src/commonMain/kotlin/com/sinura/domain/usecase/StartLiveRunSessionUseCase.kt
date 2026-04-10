package com.sinura.domain.usecase

import com.sinura.domain.model.LiveRunParticipant
import com.sinura.domain.model.LiveRunSession
import com.sinura.domain.model.LiveRunSessionState
import com.sinura.domain.model.LiveRunSourceType
import com.sinura.domain.model.RunMode
import com.sinura.domain.model.RunParticipantStatus
import com.sinura.domain.model.RunVisibility
import com.sinura.domain.repository.LiveRunSessionRepository
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
