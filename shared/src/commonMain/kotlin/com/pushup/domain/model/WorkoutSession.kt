package com.pushup.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

/**
 * Represents a single workout session during which the user performs push-ups.
 *
 * A session begins when the user starts exercising and ends when they stop.
 * Time credits are earned based on the number and quality of push-ups performed.
 *
 * @property id Unique identifier for the session.
 * @property userId Identifier of the user who performed the session.
 * @property startedAt Timestamp when the session began.
 * @property endedAt Timestamp when the session ended, or null if still in progress.
 * @property pushUpCount Total number of push-ups completed in this session.
 * @property earnedTimeCreditSeconds Number of screen-time credit seconds earned.
 * @property quality Overall quality score for the session (0.0 = poor, 1.0 = perfect).
 * @property syncStatus Current synchronization state with the backend.
 */
@Serializable
data class WorkoutSession(
    val id: String,
    val userId: String,
    val startedAt: Instant,
    val endedAt: Instant?,
    val pushUpCount: Int,
    val earnedTimeCreditSeconds: Long,
    val quality: Float,
    val syncStatus: SyncStatus,
)
