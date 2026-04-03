package com.pushup.data.repository

import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.JoggingPlaybackEntry
import com.pushup.domain.repository.JoggingPlaybackEntryRepository
import kotlinx.coroutines.CoroutineDispatcher

class JoggingPlaybackEntryRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
) : JoggingPlaybackEntryRepository {

    private val queries get() = database.databaseQueries

    override suspend fun replaceEntriesForSession(sessionId: String, entries: List<JoggingPlaybackEntry>): Unit = safeDbCall(
        dispatcher,
        "Failed to replace jogging playback entries for session '$sessionId'",
    ) {
        database.transaction {
            queries.deleteJoggingPlaybackEntriesBySessionId(sessionId)
            entries.forEach { entry ->
                queries.insertJoggingPlaybackEntry(
                    id = entry.id,
                    sessionId = entry.sessionId,
                    source = entry.source,
                    trackTitle = entry.trackTitle,
                    artistName = entry.artistName,
                    startedAt = entry.startedAt.toEpochMilliseconds(),
                    endedAt = entry.endedAt.toEpochMilliseconds(),
                    startDistanceMeters = entry.startDistanceMeters,
                    endDistanceMeters = entry.endDistanceMeters,
                    startActiveDurationSeconds = entry.startActiveDurationSeconds,
                    endActiveDurationSeconds = entry.endActiveDurationSeconds,
                )
            }
        }
    }

    override suspend fun getBySessionId(sessionId: String): List<JoggingPlaybackEntry> = safeDbCall(
        dispatcher,
        "Failed to get jogging playback entries for session '$sessionId'",
    ) {
        queries.selectJoggingPlaybackEntriesBySessionId(sessionId)
            .executeAsList()
            .map { it.toDomain() }
    }
}
