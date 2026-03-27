package com.pushup.domain.repository

import com.pushup.domain.model.JoggingSegment

interface JoggingSegmentRepository {
    suspend fun replaceSegmentsForSession(sessionId: String, segments: List<JoggingSegment>)
    suspend fun getBySessionId(sessionId: String): List<JoggingSegment>
}
