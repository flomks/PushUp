package com.sinura.domain.model

import kotlinx.datetime.LocalDate

/**
 * Immutable snapshot of a user's daily credit balance at the end of a day.
 *
 * Written by [com.sinura.domain.usecase.ApplyDailyResetUseCase] just before
 * the daily reset is applied. This preserves the historical record of how
 * much credit was available and how much was spent on each day, enabling
 * weekly/monthly charts.
 *
 * The [date] represents the calendar day (in the device's local timezone)
 * that this snapshot covers. For example, if the reset fires at 03:00 on
 * 2026-03-18, the snapshot is written for date 2026-03-17 (the day that
 * just ended).
 *
 * @property userId Identifier of the user.
 * @property date Calendar date this snapshot covers (local timezone).
 * @property earnedSeconds Total daily budget that was available (carry-over + workout earnings).
 * @property spentSeconds Credits consumed as screen time during this day.
 * @property carryOverSeconds Credits carried over from the previous day.
 * @property workoutEarnedSeconds Credits earned from workouts during this day.
 */
data class DailyCreditSnapshot(
    val userId: String,
    val date: LocalDate,
    val earnedSeconds: Long,
    val spentSeconds: Long,
    val carryOverSeconds: Long,
    val workoutEarnedSeconds: Long,
) {
    init {
        require(userId.isNotBlank()) { "DailyCreditSnapshot.userId must not be blank" }
        require(earnedSeconds >= 0) { "earnedSeconds must be >= 0, was $earnedSeconds" }
        require(spentSeconds >= 0) { "spentSeconds must be >= 0, was $spentSeconds" }
        require(carryOverSeconds >= 0) { "carryOverSeconds must be >= 0, was $carryOverSeconds" }
        require(workoutEarnedSeconds >= 0) { "workoutEarnedSeconds must be >= 0, was $workoutEarnedSeconds" }
    }

    /** Credits that were still available at the end of this day. */
    val remainingSeconds: Long get() = (earnedSeconds - spentSeconds).coerceAtLeast(0L)

    /** Fraction of the daily budget that was used (0.0 - 1.0). */
    val usageFraction: Double get() = if (earnedSeconds > 0) {
        (spentSeconds.toDouble() / earnedSeconds).coerceIn(0.0, 1.0)
    } else 0.0
}
