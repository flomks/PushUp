package com.pushup.domain.usecase

import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.model.WorkoutSummary
import com.pushup.domain.repository.PushUpRecordRepository
import com.pushup.domain.repository.TimeCreditRepository
import com.pushup.domain.repository.UserSettingsRepository
import com.pushup.domain.repository.WorkoutSessionRepository
import kotlinx.datetime.Clock

/**
 * Use-case: Finish an active workout session and calculate earned time credits.
 *
 * When invoked, this use-case:
 * 1. Verifies the session exists and is still active.
 * 2. Sets [WorkoutSession.endedAt] to the current timestamp.
 * 3. Loads the user's [com.pushup.domain.model.UserSettings] to determine the credit formula.
 * 4. Calculates earned credits: `(pushUpCount / pushUpsPerMinuteCredit) * 60` seconds.
 * 5. Optionally applies a quality multiplier based on the session's average quality score:
 *    - quality > 0.8 → 1.5x multiplier
 *    - quality 0.5..0.8 → 1.0x (no change)
 *    - quality < 0.5 → 0.7x multiplier
 * 6. Optionally caps the earned credits against the user's daily credit cap.
 * 7. Persists the updated session and adds the earned seconds to [TimeCreditRepository].
 * 8. Returns a [WorkoutSummary] containing the finished session, all push-up records,
 *    and the total credits earned.
 *
 * @property sessionRepository Repository for reading and updating workout sessions.
 * @property recordRepository Repository for reading push-up records.
 * @property timeCreditRepository Repository for updating the user's credit balance.
 * @property settingsRepository Repository for reading user settings.
 * @property clock Clock used to set the session end timestamp.
 */
class FinishWorkoutUseCase(
    private val sessionRepository: WorkoutSessionRepository,
    private val recordRepository: PushUpRecordRepository,
    private val timeCreditRepository: TimeCreditRepository,
    private val settingsRepository: UserSettingsRepository,
    private val clock: Clock = Clock.System,
) {

    /**
     * Finishes the workout session identified by [sessionId].
     *
     * @param sessionId The ID of the active session to finish.
     * @return A [WorkoutSummary] with the completed session, all records, and earned credits.
     * @throws SessionNotFoundException if no session with [sessionId] exists.
     * @throws SessionAlreadyEndedException if the session has already been finished.
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

        val settings = settingsRepository.get(session.userId)
            ?: com.pushup.domain.model.UserSettings.default(session.userId)

        val pushUpsPerMinuteCredit = settings.pushUpsPerMinuteCredit
        val rawCredits = (session.pushUpCount.toLong() * 60L) / pushUpsPerMinuteCredit.toLong()

        val creditsAfterMultiplier = if (settings.qualityMultiplierEnabled) {
            val multiplier = when {
                session.quality > 0.8f -> 1.5
                session.quality >= 0.5f -> 1.0
                else -> 0.7
            }
            (rawCredits * multiplier).toLong()
        } else {
            rawCredits
        }

        // Apply daily credit cap if configured
        val earnedCredits = if (settings.dailyCreditCapSeconds != null) {
            val cap = settings.dailyCreditCapSeconds
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

        val records = recordRepository.getBySessionId(sessionId)
        val finishedSession = session.copy(
            endedAt = now,
            earnedTimeCreditSeconds = earnedCredits,
            syncStatus = SyncStatus.PENDING,
        )

        return WorkoutSummary(
            session = finishedSession,
            records = records,
            earnedCredits = earnedCredits,
        )
    }

    /**
     * Calculates the total credits already earned today by the user (excluding the current session).
     *
     * Used to enforce the daily credit cap.
     */
    private suspend fun getAlreadyEarnedTodaySeconds(userId: String, currentSessionId: String): Long {
        val allSessions = sessionRepository.getAllByUserId(userId)
        val now = clock.now()
        // Approximate "today" as the last 24 hours to avoid timezone complexity in the use-case layer
        val dayStartMs = now.toEpochMilliseconds() - 86_400_000L
        val dayStart = kotlinx.datetime.Instant.fromEpochMilliseconds(dayStartMs)

        return allSessions
            .filter { it.id != currentSessionId }
            .filter { it.startedAt >= dayStart }
            .sumOf { it.earnedTimeCreditSeconds }
    }
}
