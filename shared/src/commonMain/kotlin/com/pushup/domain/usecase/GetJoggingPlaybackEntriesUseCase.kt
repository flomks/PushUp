package com.pushup.domain.usecase

import com.pushup.domain.model.JoggingPlaybackEntry
import com.pushup.domain.repository.JoggingPlaybackEntryRepository

class GetJoggingPlaybackEntriesUseCase(
    private val playbackRepository: JoggingPlaybackEntryRepository,
) {
    suspend operator fun invoke(sessionId: String): List<JoggingPlaybackEntry> {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }
        return playbackRepository.getBySessionId(sessionId)
    }
}
