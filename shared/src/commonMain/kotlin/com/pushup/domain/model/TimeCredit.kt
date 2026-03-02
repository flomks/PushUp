package com.pushup.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

/**
 * Tracks the screen-time credits a user has earned and spent.
 *
 * Credits are earned by completing push-up sessions and spent when
 * the user consumes screen time. The [availableSeconds] property is
 * a computed convenience that reflects the current balance.
 *
 * @property userId Identifier of the user who owns these credits.
 * @property totalEarnedSeconds Cumulative seconds earned across all sessions.
 * @property totalSpentSeconds Cumulative seconds consumed as screen time.
 * @property availableSeconds Current balance (earned minus spent).
 * @property lastUpdatedAt Timestamp of the most recent credit change.
 * @property syncStatus Current synchronization state with the backend.
 */
@Serializable
data class TimeCredit(
    val userId: String,
    val totalEarnedSeconds: Long,
    val totalSpentSeconds: Long,
    val availableSeconds: Long = totalEarnedSeconds - totalSpentSeconds,
    val lastUpdatedAt: Instant,
    val syncStatus: SyncStatus,
)
