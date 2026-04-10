package com.sinura.domain.usecase

import com.sinura.domain.model.ExerciseType
import com.sinura.domain.model.LevelCalculator
import com.sinura.domain.model.SyncStatus
import com.sinura.domain.model.UserSettings
import com.sinura.domain.model.WorkoutSession
import com.sinura.domain.model.WorkoutSummary
import com.sinura.domain.repository.ExerciseLevelRepository
import com.sinura.domain.repository.LevelRepository
import com.sinura.domain.repository.PushUpRecordRepository
import com.sinura.domain.repository.TimeCreditRepository
import com.sinura.domain.repository.UserSettingsRepository
import com.sinura.domain.repository.WorkoutSessionRepository
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.toLocalDateTime

/**
 * Use-case: Finish an active workout session and calculate earned time credits.
 *
 * When invoked, this use-case:
 * 1. Verifies the session exists and is still active.
 * 2. Loads the user's [UserSettings] to determine the credit formula.
 * 3. Calculates earned credits using floor division:
 *    `(pushUpCount / pushUpsPerMinuteCredit) * 60` seconds.
 *    Floor division is intentional — partial minutes do not earn credits.
 * 4. Optionally applies a quality multiplier based on the session's average quality score:
 *    - quality > 0.8 → 1.5x multiplier
 *    - quality 0.5..0.8 → 1.0x (no change)
 *    - quality < 0.5 → 0.7x multiplier
 * 5. Optionally caps the earned credits against the user's daily credit cap.
 *    "Today" is defined as the current calendar day in [timeZone], not a rolling 24-hour window.
 * 6. Persists the finished session and adds the earned seconds to [TimeCreditRepository].
 * 7. Returns a [WorkoutSummary] containing the finished session (re-read from DB),
 *    all push-up records, and the total credits earned.
 *
 * @property sessionRepository Repository for reading and updating workout sessions.
 * @property recordRepository Repository for reading push-up records.
 * @property timeCreditRepository Repository for updating the user's credit balance.
 * @property settingsRepository Repository for reading user settings.
 * @property levelRepository Optional repository for updating the user's account-wide XP / level.
 *   When `null`, the level system is skipped and [WorkoutSummary.earnedXp] will be 0.
 * @property exerciseLevelRepository Optional repository for updating per-exercise XP / level.
 *   When `null`, exercise-level tracking is skipped silently.
 * @property clock Clock used to set the session end timestamp.
 * @property timeZone Timezone used to determine the current calendar day for the daily cap.
 *   Defaults to the system default timezone.
 */
class FinishWorkoutUseCase(
    private val sessionRepository: WorkoutSessionRepository,
    private val recordRepository: PushUpRecordRepository,
    private val timeCreditRepository: TimeCreditRepository,
    private val settingsRepository: UserSettingsRepository,
    private val levelRepository: LevelRepository? = null,
    private val exerciseLevelRepository: ExerciseLevelRepository? = null,
    private val clock: Clock = Clock.System,
    private val timeZone: TimeZone = TimeZone.currentSystemDefault(),
) {

    /**
     * Finishes the workout session identified by [sessionId].
     *
     * @param sessionId The ID of the active session to finish.
     * @return A [WorkoutSummary] with the completed session, all records, and earned credits.
     * @throws IllegalArgumentException if [sessionId] is blank.
     * @throws SessionNotFoundException if no session with [sessionId] exists.
     * @throws SessionAlreadyEndedException if the session has already been finished.
     * @throws EmptyWorkoutDiscardedException if the session has 0 push-ups (session is deleted).
     */
    suspend operator fun invoke(sessionId: String): WorkoutSummary {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }

        val session = sessionRepository.getById(sessionId)
            ?: throw SessionNotFoundException("Session '$sessionId' not found")

        if (!session.isActive) {
            throw SessionAlreadyEndedException(
                "Session '$sessionId' has already ended at ${session.endedAt}",
            )
        }

        // Discard sessions with zero push-ups: delete from DB and do not
        // count as a completed training (no credits, no XP, no sync).
        if (session.pushUpCount == 0) {
            sessionRepository.delete(sessionId)
            throw EmptyWorkoutDiscardedException(
                "Session '$sessionId' had 0 push-ups and was discarded",
            )
        }

        val settings = settingsRepository.get(session.userId)
            ?: UserSettings.default(session.userId).also { settingsRepository.update(it) }

        // Floor division is intentional: partial minutes do not earn credits.
        val rawCredits = (session.pushUpCount.toLong() * 60L) / settings.pushUpsPerMinuteCredit.toLong()

        val creditsAfterMultiplier: Long = if (settings.qualityMultiplierEnabled) {
            val multiplier: Double = when {
                session.quality > 0.8f -> 1.5
                session.quality >= 0.5f -> 1.0
                else -> 0.7
            }
            (rawCredits * multiplier).toLong()
        } else {
            rawCredits
        }

        // Apply daily credit cap if configured.
        // "Today" is the current calendar day in the configured timezone -- not a rolling 24h window.
        val earnedCredits: Long = if (settings.dailyCreditCapSeconds != null) {
            val cap: Long = settings.dailyCreditCapSeconds
            val alreadyEarnedToday = getAlreadyEarnedTodaySeconds(session.userId, sessionId)
            val remaining = (cap - alreadyEarnedToday).coerceAtLeast(0L)
            creditsAfterMultiplier.coerceAtMost(remaining)
        } else {
            creditsAfterMultiplier
        }

        val now = clock.now()
        // Use finishSession() (a targeted UPDATE) instead of save() (INSERT OR REPLACE)
        // to avoid triggering ON DELETE CASCADE on PushUpRecord child rows.
        sessionRepository.finishSession(
            id = sessionId,
            endedAt = now,
            earnedTimeCreditSeconds = earnedCredits,
        )

        if (earnedCredits > 0) {
            timeCreditRepository.addEarnedSeconds(session.userId, earnedCredits)
        }

        // Award XP to the activity itself. Account-wide XP is derived from the
        // sum of all activity-specific XP totals.
        val earnedXp = LevelCalculator.calculateExerciseXp(
            exerciseType = ExerciseType.PUSH_UPS,
            amount = session.pushUpCount,
            quality = session.quality,
        )
        if (earnedXp > 0) {
            exerciseLevelRepository?.addXp(session.userId, ExerciseType.PUSH_UPS, earnedXp)
        }
        val updatedLevel = levelRepository?.getOrCreate(session.userId)

        val records = recordRepository.getBySessionId(sessionId)
        // Re-read the session from the DB to ensure the returned summary reflects
        // exactly what was persisted (avoids stale-snapshot inconsistencies).
        val finishedSession = sessionRepository.getById(sessionId)
            ?: error("Session '$sessionId' disappeared after finishSession() -- this should never happen")

        return WorkoutSummary(
            session = finishedSession,
            records = records,
            earnedCredits = earnedCredits,
            earnedXp = earnedXp,
            updatedLevel = updatedLevel,
        )
    }

    /**
     * Calculates the total credits already earned today by the user (excluding the current session).
     *
     * "Today" is defined as the current calendar day in [timeZone], starting at midnight.
     * Uses [WorkoutSessionRepository.getByDateRange] to avoid loading the full session history.
     */
    private suspend fun getAlreadyEarnedTodaySeconds(userId: String, currentSessionId: String): Long {
        val now = clock.now()
        val todayStart: Instant = now.toLocalDateTime(timeZone).date.atStartOfDayIn(timeZone)

        return sessionRepository
            .getByDateRange(userId, from = todayStart, to = now)
            .filter { it.id != currentSessionId }
            .sumOf { it.earnedTimeCreditSeconds }
    }
}
