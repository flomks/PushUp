package com.sinura.domain.repository

import com.sinura.domain.model.JoggingSegment

interface JoggingSegmentRepository {
    suspend fun replaceSegmentsForSession(sessionId: String, segments: List<JoggingSegment>)
    suspend fun getBySessionId(sessionId: String): List<JoggingSegment>
}
