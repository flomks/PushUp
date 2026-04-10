package com.sinura.domain.usecase

import com.sinura.domain.model.JoggingSegment
import com.sinura.domain.repository.JoggingSegmentRepository

class GetJoggingSegmentsUseCase(
    private val segmentRepository: JoggingSegmentRepository,
) {
    suspend operator fun invoke(sessionId: String): List<JoggingSegment> {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }
        return segmentRepository.getBySessionId(sessionId)
    }
}
