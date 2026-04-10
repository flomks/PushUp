package com.sinura.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

@Serializable
enum class JoggingSegmentType {
    RUN,
    PAUSE,
}

@Serializable
data class JoggingSegment(
    val id: String,
    val sessionId: String,
    val type: JoggingSegmentType,
    val startedAt: Instant,
    val endedAt: Instant?,
    val distanceMeters: Double,
    val durationSeconds: Long,
) {
    init {
        require(id.isNotBlank()) { "JoggingSegment.id must not be blank" }
        require(sessionId.isNotBlank()) { "JoggingSegment.sessionId must not be blank" }
        require(distanceMeters >= 0.0) { "JoggingSegment.distanceMeters must be >= 0, was $distanceMeters" }
        require(durationSeconds >= 0L) { "JoggingSegment.durationSeconds must be >= 0, was $durationSeconds" }
        endedAt?.let { end ->
            require(end >= startedAt) {
                "JoggingSegment.endedAt ($end) must not precede startedAt ($startedAt)"
            }
        }
    }
}
