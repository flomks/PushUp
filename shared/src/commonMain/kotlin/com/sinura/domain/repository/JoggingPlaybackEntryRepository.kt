package com.sinura.domain.repository

import com.sinura.domain.model.JoggingPlaybackEntry

interface JoggingPlaybackEntryRepository {
    suspend fun replaceEntriesForSession(sessionId: String, entries: List<JoggingPlaybackEntry>)
    suspend fun getBySessionId(sessionId: String): List<JoggingPlaybackEntry>
}
