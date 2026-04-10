package com.sinura.domain.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

/**
 * Aggregated view of a completed workout session together with
 * its individual push-up records, the credits that were earned, and the
 * XP / level update from the level system.
 *
 * This model is typically used on the post-workout summary screen.
 *
 * @property session The completed workout session.
 * @property records All individual push-up records captured during the session.
 * @property earnedCredits Total screen-time credit seconds earned in this session.
 * @property earnedXp XP earned in this session (0 when the level system is not active).
 * @property updatedLevel The user's [UserLevel] after XP has been applied, or `null`
 *   if the level system is not yet initialised for this user.
 */
@Serializable
data class WorkoutSummary(
    val session: WorkoutSession,
    val records: List<PushUpRecord>,
    val earnedCredits: Long,
    val earnedXp: Long = 0L,
    val updatedLevel: UserLevel? = null,
) {
    init {
        require(earnedCredits >= 0) {
            "WorkoutSummary.earnedCredits must be >= 0, was $earnedCredits"
        }
        require(earnedXp >= 0) {
            "WorkoutSummary.earnedXp must be >= 0, was $earnedXp"
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
