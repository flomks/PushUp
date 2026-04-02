package com.pushup.domain.usecase

import com.pushup.domain.model.LiveRunSession
import com.pushup.domain.repository.LiveRunSessionRepository

class ObserveFriendsActiveRunsUseCase(
    private val repository: LiveRunSessionRepository,
) {
    suspend operator fun invoke(userId: String): List<LiveRunSession> {
        require(userId.isNotBlank()) { "userId must not be blank" }
        return repository.getFriendsActiveSessions(userId)
    }
}
