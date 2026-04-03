package com.pushup.domain.repository

import com.pushup.domain.model.JoggingPlaybackEntry

interface JoggingPlaybackEntryRepository {
    suspend fun replaceEntriesForSession(sessionId: String, entries: List<JoggingPlaybackEntry>)
    suspend fun getBySessionId(sessionId: String): List<JoggingPlaybackEntry>
}
