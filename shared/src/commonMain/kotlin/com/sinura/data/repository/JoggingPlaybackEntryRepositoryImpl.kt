package com.sinura.data.repository

import com.sinura.data.mapper.toDomain
import com.sinura.db.SinuraDatabase
import com.sinura.domain.model.JoggingPlaybackEntry
import com.sinura.domain.repository.JoggingPlaybackEntryRepository
import kotlinx.coroutines.CoroutineDispatcher

class JoggingPlaybackEntryRepositoryImpl(
    private val database: SinuraDatabase,
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
                    spotifyTrackUri = entry.spotifyTrackUri,
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
