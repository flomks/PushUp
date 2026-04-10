package com.sinura.domain.usecase

import com.sinura.domain.model.JoggingPlaybackEntry
import com.sinura.domain.repository.JoggingPlaybackEntryRepository

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
