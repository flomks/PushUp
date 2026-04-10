package com.sinura.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

/**
 * Represents a single push-up repetition captured during a [WorkoutSession].
 *
 * Each record contains timing and quality metrics for an individual push-up,
 * enabling detailed analysis of form and performance over time.
 *
 * @property id Unique identifier for this record.
 * @property sessionId Identifier of the parent [WorkoutSession].
 * @property timestamp The moment this push-up was recorded.
 * @property durationMs Time in milliseconds to complete this single push-up.
 * @property depthScore How deep the push-up went (0.0 = shallow, 1.0 = full depth).
 * @property formScore Overall form quality (0.0 = poor form, 1.0 = perfect form).
 */
@Serializable
data class PushUpRecord(
    val id: String,
    val sessionId: String,
    val timestamp: Instant,
    val durationMs: Long,
    val depthScore: Float,
    val formScore: Float,
) {
    init {
        require(id.isNotBlank()) { "PushUpRecord.id must not be blank" }
        require(sessionId.isNotBlank()) { "PushUpRecord.sessionId must not be blank" }
        require(durationMs > 0) { "PushUpRecord.durationMs must be > 0, was $durationMs" }
        require(depthScore in 0f..1f) { "PushUpRecord.depthScore must be in [0, 1], was $depthScore" }
        require(formScore in 0f..1f) { "PushUpRecord.formScore must be in [0, 1], was $formScore" }
    }

    /** Combined quality metric averaging depth and form (0.0 - 1.0). */
    val combinedScore: Float get() = (depthScore + formScore) / 2f
}
