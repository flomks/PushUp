package com.pushup.domain.model

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
)
