package com.sinura.domain.usecase

import com.sinura.domain.model.JoggingPlaybackEntry
import com.sinura.domain.repository.JoggingPlaybackEntryRepository

class GetJoggingPlaybackEntriesUseCase(
    private val playbackRepository: JoggingPlaybackEntryRepository,
) {
    suspend operator fun invoke(sessionId: String): List<JoggingPlaybackEntry> {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }
        return playbackRepository.getBySessionId(sessionId)
    }
}
