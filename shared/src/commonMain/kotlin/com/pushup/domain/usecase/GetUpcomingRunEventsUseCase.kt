package com.pushup.domain.usecase

import com.pushup.domain.model.RunEvent
import com.pushup.domain.repository.RunEventRepository

class GetUpcomingRunEventsUseCase(
    private val repository: RunEventRepository,
) {
    suspend operator fun invoke(userId: String): List<RunEvent> {
        require(userId.isNotBlank()) { "userId must not be blank" }
        return repository.getUpcomingForUser(userId)
    }
}
