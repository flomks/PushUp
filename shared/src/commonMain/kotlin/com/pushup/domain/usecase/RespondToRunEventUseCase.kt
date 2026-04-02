package com.pushup.domain.usecase

import com.pushup.domain.model.RunEventParticipant
import com.pushup.domain.model.RunParticipantStatus
import com.pushup.domain.repository.RunEventRepository

class RespondToRunEventUseCase(
    private val repository: RunEventRepository,
) {
    suspend operator fun invoke(
        eventId: String,
        userId: String,
        accept: Boolean,
    ): RunEventParticipant {
        require(eventId.isNotBlank()) { "eventId must not be blank" }
        require(userId.isNotBlank()) { "userId must not be blank" }

        return repository.updateParticipantStatus(
            eventId = eventId,
            userId = userId,
            status = if (accept) RunParticipantStatus.ACCEPTED else RunParticipantStatus.DECLINED,
        )
    }
}
