package com.pushup.domain.usecase

import com.pushup.domain.repository.RunEventRepository

class DeleteRunEventUseCase(
    private val repository: RunEventRepository,
) {
    suspend operator fun invoke(
        eventId: String,
        userId: String,
    ) {
        require(eventId.isNotBlank()) { "eventId must not be blank" }
        require(userId.isNotBlank()) { "userId must not be blank" }

        val event = repository.getById(eventId)
            ?: error("Run event not found: $eventId")
        require(event.createdBy == userId) {
            "Only the organizer can delete run event '$eventId'"
        }

        repository.deleteEvent(eventId)
    }
}
