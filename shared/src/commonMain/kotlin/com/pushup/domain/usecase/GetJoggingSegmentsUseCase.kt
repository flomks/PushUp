package com.pushup.domain.usecase

import com.pushup.domain.model.JoggingSegment
import com.pushup.domain.repository.JoggingSegmentRepository

class GetJoggingSegmentsUseCase(
    private val segmentRepository: JoggingSegmentRepository,
) {
    suspend operator fun invoke(sessionId: String): List<JoggingSegment> {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }
        return segmentRepository.getBySessionId(sessionId)
    }
}
