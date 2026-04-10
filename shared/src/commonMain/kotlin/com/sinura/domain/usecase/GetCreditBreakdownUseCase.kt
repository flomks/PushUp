package com.sinura.domain.usecase

import com.sinura.domain.model.TimeCredit
import com.sinura.domain.repository.TimeCreditRepository
import com.sinura.domain.repository.WorkoutSessionRepository
import kotlin.time.Duration.Companion.hours
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.toLocalDateTime

/**
 * Use-case: Compute a detailed breakdown of the current daily credit balance.
 *
 * This is a **read-only** use-case that does not mutate any data. It inspects
 * the current [TimeCredit] and today's workout sessions to determine how the
 * daily balance is composed:
 *
 * - **Carry-over (20%)**: Credits carried over from the previous day at 20%.
 * - **Carry-over (02-03 window)**: Credits earned between 02:00-03:00 that
 *   were carried over at 100%.
 * - **Today's workouts**: Credits earned from workouts completed after the
 *   most recent reset boundary (03:00).
 * - **Spent today**: Credits consumed as screen time today.
 *
 * @property timeCreditRepository Repository for reading credit records.
 * @property sessionRepository Repository for querying workout sessions.
 * @property clock Clock used for determining the current time.
 * @property timeZone Timezone used to determine the reset boundary.
 */
class GetCreditBreakdownUseCase(
    private val timeCreditRepository: TimeCreditRepository,
    private val sessionRepository: WorkoutSessionRepository,
    private val applyDailyResetUseCase: ApplyDailyResetUseCase? = null,
    private val clock: Clock = Clock.System,
    private val timeZone: TimeZone = TimeZone.currentSystemDefault(),
) {

    /**
     * Computes the credit breakdown for [userId].
     *
     * @return A [CreditBreakdown] with all components, or `null` if no credit record exists.
     */
    suspend operator fun invoke(userId: String): CreditBreakdown? {
        require(userId.isNotBlank()) { "userId must not be blank" }

        val credit = applyDailyResetUseCase?.invoke(userId) ?: timeCreditRepository.get(userId) ?: return null
        val now = clock.now()

        // Calculate the most recent reset boundary (03:00 local time).
        val mostRecentReset = mostRecentResetBoundary(now)

        // Credits earned from workouts completed AFTER the reset boundary.
        val todayWorkoutEarned = getEarnedAfterReset(userId, mostRecentReset, now)

        // Credits earned in the 02:00-03:00 window (100% carry-over).
        val windowStart = mostRecentReset.minus(TimeCredit.FULL_CARRY_OVER_WINDOW_HOURS.hours)
        val lateNightEarned = getEarnedInWindow(userId, windowStart, mostRecentReset)

        // The carry-over from the 20% rule:
        // dailyEarnedSeconds = carryOver20pct + lateNightCarryOver + todayWorkoutEarned
        // So: carryOver20pct = dailyEarnedSeconds - lateNightEarned - todayWorkoutEarned
        val carryOver20pct = (credit.dailyEarnedSeconds - lateNightEarned - todayWorkoutEarned)
            .coerceAtLeast(0L)

        return CreditBreakdown(
            availableSeconds = credit.availableSeconds,
            dailyEarnedSeconds = credit.dailyEarnedSeconds,
            dailySpentSeconds = credit.dailySpentSeconds,
            todayWorkoutEarned = todayWorkoutEarned,
            carryOverPercentSeconds = carryOver20pct,
            carryOverLateNightSeconds = lateNightEarned,
            totalEarnedSeconds = credit.totalEarnedSeconds,
            totalSpentSeconds = credit.totalSpentSeconds,
        )
    }

    /**
     * Calculates the most recent reset boundary (03:00 local time) at or before [now].
     */
    private fun mostRecentResetBoundary(now: Instant): Instant {
        val localNow = now.toLocalDateTime(timeZone)
        val todayDate = localNow.date
        val todayResetInstant = todayDate.atStartOfDayIn(timeZone)
            .plus(TimeCredit.DAILY_RESET_HOUR.hours)

        return if (now >= todayResetInstant) {
            todayResetInstant
        } else {
            todayDate.atStartOfDayIn(timeZone)
                .plus(TimeCredit.DAILY_RESET_HOUR.hours)
                .minus(24.hours)
        }
    }

    /**
     * Sums earned credits from sessions that ended within [from, to).
     */
    private suspend fun getEarnedInWindow(userId: String, from: Instant, to: Instant): Long {
        return sessionRepository
            .getByEndedAtRange(userId, from = from, to = to)
            .sumOf { it.earnedTimeCreditSeconds }
    }

    /**
     * Sums earned credits from sessions that ended after [resetBoundary] up to [now].
     */
    private suspend fun getEarnedAfterReset(userId: String, resetBoundary: Instant, now: Instant): Long {
        return sessionRepository
            .getByEndedAtRange(userId, from = resetBoundary, to = now)
            .sumOf { it.earnedTimeCreditSeconds }
    }
}

/**
 * Detailed breakdown of the current daily credit balance.
 *
 * All values are in seconds.
 */
data class CreditBreakdown(
    /** Current available balance (dailyEarned - dailySpent, clamped to >= 0). */
    val availableSeconds: Long,
    /** Total daily budget (carry-overs + today's earnings). */
    val dailyEarnedSeconds: Long,
    /** Credits spent as screen time today. */
    val dailySpentSeconds: Long,
    /** Credits earned from workouts completed after the 03:00 reset. */
    val todayWorkoutEarned: Long,
    /** Credits carried over from the previous day at 20%. */
    val carryOverPercentSeconds: Long,
    /** Credits earned between 02:00-03:00 and carried over at 100%. */
    val carryOverLateNightSeconds: Long,
    /** All-time total earned (for stats display). */
    val totalEarnedSeconds: Long,
    /** All-time total spent (for stats display). */
    val totalSpentSeconds: Long,
)
