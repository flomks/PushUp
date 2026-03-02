package com.pushup.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

/**
 * Tracks the screen-time credits a user has earned and spent.
 *
 * Credits are earned by completing push-up sessions and spent when
 * the user consumes screen time. The [availableSeconds] property is
 * a derived value that always reflects `totalEarnedSeconds - totalSpentSeconds`,
 * ensuring consistency regardless of how the instance was constructed.
 *
 * @property userId Identifier of the user who owns these credits.
 * @property totalEarnedSeconds Cumulative seconds earned across all sessions.
 * @property totalSpentSeconds Cumulative seconds consumed as screen time.
 * @property lastUpdatedAt Timestamp of the most recent credit change.
 * @property syncStatus Current synchronization state with the backend.
 */
@Serializable
data class TimeCredit(
    val userId: String,
    val totalEarnedSeconds: Long,
    val totalSpentSeconds: Long,
    val lastUpdatedAt: Instant,
    val syncStatus: SyncStatus,
) {
    init {
        require(userId.isNotBlank()) { "TimeCredit.userId must not be blank" }
        require(totalEarnedSeconds >= 0) {
            "TimeCredit.totalEarnedSeconds must be >= 0, was $totalEarnedSeconds"
        }
        require(totalSpentSeconds >= 0) {
            "TimeCredit.totalSpentSeconds must be >= 0, was $totalSpentSeconds"
        }
    }

    /**
     * Current credit balance (earned minus spent).
     *
     * This is a computed property -- always consistent, never stale,
     * and excluded from serialization via [Transient].
     */
    @Transient
    val availableSeconds: Long = totalEarnedSeconds - totalSpentSeconds

    /** `true` when the user has remaining credits to spend. */
    @Transient
    val hasCredits: Boolean = availableSeconds > 0
}
