package com.pushup.data.repository

import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.JoggingSegment
import com.pushup.domain.model.JoggingSegmentType
import com.pushup.domain.repository.JoggingSegmentRepository
import kotlinx.coroutines.CoroutineDispatcher

class JoggingSegmentRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
) : JoggingSegmentRepository {

    private val queries get() = database.databaseQueries

    override suspend fun replaceSegmentsForSession(sessionId: String, segments: List<JoggingSegment>): Unit = safeDbCall(
        dispatcher,
        "Failed to replace jogging segments for session '$sessionId'",
    ) {
        database.transaction {
            queries.deleteJoggingSegmentsBySessionId(sessionId)
            segments.forEach { segment ->
                queries.insertJoggingSegment(
                    id = segment.id,
                    sessionId = segment.sessionId,
                    type = if (segment.type == JoggingSegmentType.PAUSE) "pause" else "run",
                    startedAt = segment.startedAt.toEpochMilliseconds(),
                    endedAt = segment.endedAt?.toEpochMilliseconds(),
                    distanceMeters = segment.distanceMeters,
                    durationSeconds = segment.durationSeconds,
                )
            }
        }
    }

    override suspend fun getBySessionId(sessionId: String): List<JoggingSegment> = safeDbCall(
        dispatcher,
        "Failed to get jogging segments for session '$sessionId'",
    ) {
        queries.selectJoggingSegmentsBySessionId(sessionId)
            .executeAsList()
            .map { it.toDomain() }
    }
}
