package com.sinura.domain.usecase

import com.sinura.domain.model.RunEvent
import com.sinura.domain.model.RunEventParticipant
import com.sinura.domain.model.RunParticipantRole
import com.sinura.domain.model.RunParticipantStatus
import com.sinura.domain.repository.RunEventRepository

data class LeaveRunEventResult(
    val event: RunEvent,
    val participant: RunEventParticipant,
    val newOrganizerUserId: String?,
)

class LeaveRunEventUseCase(
    private val repository: RunEventRepository,
) {
    suspend operator fun invoke(
        eventId: String,
        userId: String,
    ): LeaveRunEventResult {
        require(eventId.isNotBlank()) { "eventId must not be blank" }
        require(userId.isNotBlank()) { "userId must not be blank" }

        val event = repository.getById(eventId)
            ?: error("Run event not found: $eventId")
        val participants = repository.getParticipants(eventId)
        val participant = participants.firstOrNull { it.userId == userId }
            ?: error("Participant '$userId' not found in run event '$eventId'")

        val newOrganizer = if (event.createdBy == userId) {
            val eligibleParticipants = participants.filter {
                it.userId != userId &&
                    (it.status == RunParticipantStatus.ACCEPTED || it.status == RunParticipantStatus.CHECKED_IN)
            }
            EventOrganizerSelectionPolicy.selectNextOrganizer(eligibleParticipants)
                ?: error("Run event '$eventId' has no eligible participant to take over.")
        } else {
            null
        }

        if (newOrganizer != null) {
            repository.updateEventOrganizer(eventId, newOrganizer.userId)
            repository.updateParticipantRole(
                eventId = eventId,
                userId = newOrganizer.userId,
                role = RunParticipantRole.ORGANIZER,
            )
        }

        repository.removeParticipant(eventId, userId)

        return LeaveRunEventResult(
            event = repository.getById(eventId) ?: event,
            participant = participant,
            newOrganizerUserId = newOrganizer?.userId,
        )
    }
}
