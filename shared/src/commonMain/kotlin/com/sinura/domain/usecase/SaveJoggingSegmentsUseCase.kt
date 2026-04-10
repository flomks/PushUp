package com.sinura.domain.usecase

import com.sinura.domain.model.JoggingSegment
import com.sinura.domain.repository.JoggingSegmentRepository

class SaveJoggingSegmentsUseCase(
    private val segmentRepository: JoggingSegmentRepository,
) {
    suspend operator fun invoke(sessionId: String, segments: List<JoggingSegment>) {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }
        if (segments.any { it.sessionId != sessionId }) {
            throw IllegalArgumentException("All jogging segments must belong to session '$sessionId'")
        }
        segmentRepository.replaceSegmentsForSession(sessionId, segments)
    }
}
