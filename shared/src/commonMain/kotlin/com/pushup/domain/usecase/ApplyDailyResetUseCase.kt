package com.pushup.domain.usecase

import com.pushup.domain.model.DailyCreditSnapshot
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.repository.DailyCreditSnapshotRepository
import com.pushup.domain.repository.TimeCreditRepository
import com.pushup.domain.repository.WorkoutSessionRepository
import kotlin.time.Duration.Companion.hours
import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.minus
import kotlinx.datetime.toLocalDateTime

/**
 * Use-case: Apply the daily credit reset with carry-over logic.
 *
 * ## Reset Rules
 * Every day at [TimeCredit.DAILY_RESET_HOUR] (03:00) in the device's local
 * timezone, the daily credit balance is reset:
 *
 * 1. Credits earned in the **last hour** before the reset boundary (02:00-03:00)
 *    are carried over at **100%**.
 * 2. All other remaining credits are carried over at **[TimeCredit.CARRY_OVER_RATIO]** (20%).
 * 3. The new daily balance = (100% carry-over) + (20% of the rest).
 *
 * ## Snapshot
 * Before applying the reset, a [DailyCreditSnapshot] is written for the day
 * that just ended. This preserves the historical record of how much credit
 * was available and how much was spent, enabling weekly/monthly charts.
 *
 * ## When is this called?
 * This use-case should be invoked lazily -- whenever the credit balance is
 * read or observed. It checks whether the reset boundary has been crossed
 * since [TimeCredit.lastResetAt] and applies the reset if needed.
 *
 * ## Legacy migration
 * For records where [TimeCredit.lastResetAt] is `null` (pre-migration), the
 * first invocation sets `lastResetAt` to the most recent reset boundary
 * without zeroing the balance, preserving the user's existing credits.
 *
 * @property timeCreditRepository Repository for reading and updating credit records.
 * @property sessionRepository Repository for querying workout sessions by endedAt range.
 * @property snapshotRepository Repository for persisting daily credit snapshots.
 * @property clock Clock used for determining the current time.
 * @property timeZone Timezone used to determine the reset boundary.
 */
class ApplyDailyResetUseCase(
    private val timeCreditRepository: TimeCreditRepository,
    private val sessionRepository: WorkoutSessionRepository,
    private val snapshotRepository: DailyCreditSnapshotRepository? = null,
    private val clock: Clock = Clock.System,
    private val timeZone: TimeZone = TimeZone.currentSystemDefault(),
) {

    /**
     * Checks whether a daily reset is due for [userId] and applies it if so.
     *
     * @param userId The ID of the user whose credits to check.
     * @return The (possibly reset) [TimeCredit], or `null` if no record exists.
     */
    suspend operator fun invoke(userId: String): TimeCredit? {
        require(userId.isNotBlank()) { "userId must not be blank" }

        val credit = timeCreditRepository.get(userId) ?: return null
        val now = clock.now()

        // Calculate the most recent reset boundary (03:00 local time).
        val mostRecentReset = mostRecentResetBoundary(now)

        // Legacy migration: if lastResetAt is null, this is a pre-migration record.
        // Set lastResetAt to the most recent boundary without resetting the balance.
        if (credit.lastResetAt == null) {
            val migrated = credit.copy(
                lastResetAt = mostRecentReset,
                syncStatus = SyncStatus.PENDING,
                lastUpdatedAt = now,
            )
            timeCreditRepository.update(migrated)
            return migrated
        }

        // No reset needed if we haven't crossed the boundary.
        if (credit.lastResetAt >= mostRecentReset) {
            return credit
        }

        // A reset is due. Apply each missed daily boundary one by one so carry-over
        // compounds correctly day-by-day (instead of a single reset over many days).
        var workingCredit = credit
        var boundary = nextResetBoundary(credit.lastResetAt)

        while (boundary <= mostRecentReset) {
            // Save snapshot for the day that just ended at this boundary.
            saveSnapshot(userId, workingCredit, boundary)

            val currentAvailable = workingCredit.availableSeconds
            val nextDailyEarned = if (currentAvailable <= 0L) {
                0L
            } else {
                // Credits earned in the full-carry-over window (02:00-03:00).
                val windowStart = boundary.minus(
                    TimeCredit.FULL_CARRY_OVER_WINDOW_HOURS.hours,
                )
                val recentEarned = getEarnedInWindow(userId, windowStart, boundary)

                // Credits NOT earned in the recent window = the rest of the available balance.
                val nonRecentAvailable = (currentAvailable - recentEarned).coerceAtLeast(0L)

                // Carry-over calculation:
                //   100% of recent credits + 20% of the rest
                (recentEarned + (nonRecentAvailable * TimeCredit.CARRY_OVER_RATIO).toLong())
                    .coerceAtLeast(0L)
            }

            workingCredit = workingCredit.copy(
                dailyEarnedSeconds = nextDailyEarned,
                dailySpentSeconds = 0L,
                lastResetAt = boundary,
                lastUpdatedAt = now,
                syncStatus = SyncStatus.PENDING,
            )

            boundary = nextResetBoundary(boundary)
        }

        timeCreditRepository.update(workingCredit)
        return workingCredit
    }

    /**
     * Calculates the most recent reset boundary (03:00 local time) that is
     * at or before [now].
     *
     * If [now] is before 03:00 today, the boundary is yesterday's 03:00.
     * If [now] is at or after 03:00 today, the boundary is today's 03:00.
     */
    internal fun mostRecentResetBoundary(now: Instant): Instant {
        val localNow = now.toLocalDateTime(timeZone)
        val todayDate = localNow.date

        // Today's reset boundary: todayDate at DAILY_RESET_HOUR:00
        val todayResetInstant = todayDate.atStartOfDayIn(timeZone)
            .plus(TimeCredit.DAILY_RESET_HOUR.hours)

        return if (now >= todayResetInstant) {
            todayResetInstant
        } else {
            // Before today's reset -- use yesterday's reset boundary.
            todayDate.atStartOfDayIn(timeZone)
                .plus(TimeCredit.DAILY_RESET_HOUR.hours)
                .minus(24.hours)
        }
    }

    /**
     * Calculates the next local 03:00 reset boundary after [currentBoundary].
     */
    internal fun nextResetBoundary(currentBoundary: Instant): Instant {
        val nextDate = currentBoundary
            .toLocalDateTime(timeZone)
            .date
            .plus(1, DateTimeUnit.DAY)
        return nextDate.atStartOfDayIn(timeZone)
            .plus(TimeCredit.DAILY_RESET_HOUR.hours)
    }

    /**
     * Saves a [DailyCreditSnapshot] for the day that just ended.
     *
     * The snapshot date is the calendar day BEFORE the reset boundary.
     * For example, if the reset fires at 03:00 on 2026-03-18, the snapshot
     * is for 2026-03-17.
     *
     * The carry-over and workout-earned values are computed from the session
     * data to ensure accuracy.
     */
    private suspend fun saveSnapshot(
        userId: String,
        credit: TimeCredit,
        resetBoundary: Instant,
    ) {
        val repo = snapshotRepository ?: return

        // The snapshot covers the day before the reset boundary.
        // Reset at 03:00 on March 18 -> snapshot date is March 17.
        val resetLocal = resetBoundary.toLocalDateTime(timeZone)
        val snapshotDate = resetLocal.date.minus(1, DateTimeUnit.DAY)

        // Calculate workout-earned for the ending day:
        // Sessions that ended between the PREVIOUS reset and this reset.
        val previousReset = resetBoundary.minus(24.hours)
        val workoutEarned = getEarnedInWindow(userId, previousReset, resetBoundary)

        // Carry-over = dailyEarned - workoutEarned (what was brought from the day before).
        val carryOver = (credit.dailyEarnedSeconds - workoutEarned).coerceAtLeast(0L)

        val snapshot = DailyCreditSnapshot(
            userId = userId,
            date = snapshotDate,
            earnedSeconds = credit.dailyEarnedSeconds,
            spentSeconds = credit.dailySpentSeconds,
            carryOverSeconds = carryOver,
            workoutEarnedSeconds = workoutEarned,
        )

        try {
            repo.save(snapshot)
        } catch (_: Exception) {
            // Best-effort: snapshot failure must not block the reset.
        }
    }

    /**
     * Sums the `earnedTimeCreditSeconds` of all completed sessions whose
     * `endedAt` falls within [[from], [to]).
     *
     * Uses `endedAt` because that is the moment credits are actually awarded
     * (see [FinishWorkoutUseCase]).
     */
    private suspend fun getEarnedInWindow(
        userId: String,
        from: Instant,
        to: Instant,
    ): Long {
        return sessionRepository
            .getByEndedAtRange(userId, from = from, to = to)
            .sumOf { it.earnedTimeCreditSeconds }
    }
}
