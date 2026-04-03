package com.pushup.domain.usecase

import com.pushup.domain.model.JoggingPlaybackEntry
import com.pushup.domain.repository.JoggingPlaybackEntryRepository

class SaveJoggingPlaybackEntriesUseCase(
    private val playbackRepository: JoggingPlaybackEntryRepository,
) {
    suspend operator fun invoke(sessionId: String, entries: List<JoggingPlaybackEntry>) {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }
        if (entries.any { it.sessionId != sessionId }) {
            throw IllegalArgumentException("All jogging playback entries must belong to session '$sessionId'")
        }
        playbackRepository.replaceEntriesForSession(sessionId, entries)
    }
}
