package com.sinura.domain.usecase

import com.sinura.domain.model.RunEvent
import com.sinura.domain.repository.RunEventRepository

class GetUpcomingRunEventsUseCase(
    private val repository: RunEventRepository,
) {
    suspend operator fun invoke(userId: String): List<RunEvent> {
        require(userId.isNotBlank()) { "userId must not be blank" }
        return repository.getUpcomingForUser(userId)
    }
}
