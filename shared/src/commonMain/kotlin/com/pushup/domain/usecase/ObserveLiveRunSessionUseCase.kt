package com.pushup.domain.usecase

import com.pushup.domain.model.LiveRunParticipant
import com.pushup.domain.model.LiveRunSession
import com.pushup.domain.repository.LiveRunPresenceRepository
import com.pushup.domain.repository.LiveRunSessionRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine

data class LiveRunSessionSnapshot(
    val session: LiveRunSession?,
    val participants: List<LiveRunParticipant>,
    val presenceCount: Int,
)

class ObserveLiveRunSessionUseCase(
    private val sessionRepository: LiveRunSessionRepository,
    private val presenceRepository: LiveRunPresenceRepository,
) {
    operator fun invoke(sessionId: String): Flow<LiveRunSessionSnapshot> {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }

        return combine(
            sessionRepository.observeSession(sessionId),
            sessionRepository.observeParticipants(sessionId),
            presenceRepository.observeForSession(sessionId),
        ) { session, participants, presences ->
            LiveRunSessionSnapshot(
                session = session,
                participants = participants,
                presenceCount = presences.size,
            )
        }
    }
}
