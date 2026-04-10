package com.sinura.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

/**
 * Tracks the screen-time credits a user has earned and spent.
 *
 * ## Daily Reset with Carry-Over
 * Credits are not permanent. Every day at 03:00 local device time, the
 * credit balance is reset with a carry-over mechanism:
 *
 * 1. Credits earned in the **last hour before reset** (02:00-03:00) are
 *    carried over at **100%**.
 * 2. All other remaining credits are carried over at **20%**.
 *
 * This prevents credits from accumulating indefinitely while being fair
 * to users who work out late at night.
 *
 * ## Fields
 * The [availableSeconds] property is a derived value that always reflects
 * `dailyEarnedSeconds - dailySpentSeconds`, ensuring consistency.
 *
 * @property userId Identifier of the user who owns these credits.
 * @property totalEarnedSeconds Cumulative seconds earned across all sessions (all-time, for stats).
 * @property totalSpentSeconds Cumulative seconds consumed as screen time (all-time, for stats).
 * @property dailyEarnedSeconds Credits available in the current daily period (earned + carry-over).
 * @property dailySpentSeconds Credits spent in the current daily period.
 * @property lastResetAt Timestamp of the most recent daily reset (03:00 local time).
 *   `null` for legacy records that have not yet been through a reset cycle.
 * @property lastUpdatedAt Timestamp of the most recent credit change.
 * @property syncStatus Current synchronization state with the backend.
 */
@Serializable
data class TimeCredit(
    val userId: String,
    val totalEarnedSeconds: Long,
    val totalSpentSeconds: Long,
    val dailyEarnedSeconds: Long,
    val dailySpentSeconds: Long,
    val lastResetAt: Instant?,
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
        require(dailyEarnedSeconds >= 0) {
            "TimeCredit.dailyEarnedSeconds must be >= 0, was $dailyEarnedSeconds"
        }
        require(dailySpentSeconds >= 0) {
            "TimeCredit.dailySpentSeconds must be >= 0, was $dailySpentSeconds"
        }
    }

    /**
     * Current credit balance for the active daily period.
     *
     * This is a computed property -- always consistent, never stale,
     * and excluded from serialization via [Transient].
     */
    @Transient
    val availableSeconds: Long = (dailyEarnedSeconds - dailySpentSeconds).coerceAtLeast(0L)

    /** `true` when the user has remaining credits to spend. */
    @Transient
    val hasCredits: Boolean = availableSeconds > 0

    companion object {
        /** Hour of day (0-23) at which the daily reset occurs in the device's local timezone. */
        const val DAILY_RESET_HOUR: Int = 3

        /** Percentage of non-recent credits carried over at reset (0.0 - 1.0). */
        const val CARRY_OVER_RATIO: Double = 0.20

        /** Duration in hours before the reset during which earned credits carry over at 100%. */
        const val FULL_CARRY_OVER_WINDOW_HOURS: Int = 1
    }
}
