package com.pushup.domain.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

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
) {
    init {
        require(earnedCredits >= 0) {
            "WorkoutSummary.earnedCredits must be >= 0, was $earnedCredits"
        }
        require(records.all { it.sessionId == session.id }) {
            "All PushUpRecords must belong to the same session (expected id=${session.id})"
        }
    }

    /** Average form score across all records, or `0f` when [records] is empty. */
    @Transient
    val averageFormScore: Float =
        if (records.isEmpty()) 0f else records.map { it.formScore }.average().toFloat()

    /** Average depth score across all records, or `0f` when [records] is empty. */
    @Transient
    val averageDepthScore: Float =
        if (records.isEmpty()) 0f else records.map { it.depthScore }.average().toFloat()
}
