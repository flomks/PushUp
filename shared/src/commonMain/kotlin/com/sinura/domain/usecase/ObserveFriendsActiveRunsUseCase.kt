package com.sinura.domain.usecase

import com.sinura.domain.model.LiveRunSession
import com.sinura.domain.repository.LiveRunSessionRepository

class ObserveFriendsActiveRunsUseCase(
    private val repository: LiveRunSessionRepository,
) {
    suspend operator fun invoke(userId: String): List<LiveRunSession> {
        require(userId.isNotBlank()) { "userId must not be blank" }
        return repository.getFriendsActiveSessions(userId)
    }
}
