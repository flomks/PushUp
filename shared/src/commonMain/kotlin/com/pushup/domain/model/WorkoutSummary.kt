package com.pushup.domain.model

import kotlinx.serialization.Serializable

/**
 * Aggregated view of a completed workout session together with
 * its individual push-up records and the credits that were earned.
 *
 * This model is typically used on the post-workout summary screen.
 *
 * @property session The completed workout session.
 * @property records All individual push-up records captured during the session.
 * @property earnedCredits Total screen-time credit seconds earned in this session.
 */
@Serializable
data class WorkoutSummary(
    val session: WorkoutSession,
    val records: List<PushUpRecord>,
    val earnedCredits: Long,
)
