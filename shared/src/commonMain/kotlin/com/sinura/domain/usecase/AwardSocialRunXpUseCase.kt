package com.sinura.domain.usecase

import com.sinura.domain.model.ExerciseLevel
import com.sinura.domain.model.ExerciseType
import com.sinura.domain.model.RunXpAward
import com.sinura.domain.model.UserLevel
import com.sinura.domain.repository.ExerciseLevelRepository
import com.sinura.domain.repository.LevelRepository
import com.sinura.domain.repository.LiveRunSessionRepository
import com.sinura.domain.repository.RunXpAwardRepository
import kotlinx.datetime.Clock

data class AwardSocialRunXpResult(
    val award: RunXpAward,
    val appliedBonusXp: Long,
    val updatedExerciseLevel: ExerciseLevel?,
    val updatedUserLevel: UserLevel?,
)

class AwardSocialRunXpUseCase(
    private val liveRunSessionRepository: LiveRunSessionRepository,
    private val runXpAwardRepository: RunXpAwardRepository,
    private val exerciseLevelRepository: ExerciseLevelRepository,
    private val levelRepository: LevelRepository,
    private val clock: Clock = Clock.System,
    private val idGenerator: IdGenerator = DefaultIdGenerator,
) {
    suspend operator fun invoke(
        userId: String,
        sessionId: String,
        baseXp: Long,
    ): AwardSocialRunXpResult {
        require(userId.isNotBlank()) { "userId must not be blank" }
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }
        require(baseXp >= 0L) { "baseXp must be >= 0" }

        runXpAwardRepository.getBySessionIdAndUserId(sessionId, userId)?.let { existing ->
            return AwardSocialRunXpResult(
                award = existing,
                appliedBonusXp = 0L,
                updatedExerciseLevel = exerciseLevelRepository.get(userId, ExerciseType.JOGGING),
                updatedUserLevel = levelRepository.getOrCreate(userId),
            )
        }

        val participants = liveRunSessionRepository.getParticipants(sessionId)
        val participant = participants.firstOrNull { it.userId == userId }
            ?: error("Participant '$userId' not found in live run session '$sessionId'")
        val bonusDecision = RunXpBonusCalculator.evaluate(participant, participants)
        val totalXpAwarded = bonusDecision.apply(baseXp)
        val bonusXp = (totalXpAwarded - baseXp).coerceAtLeast(0L)
        val now = clock.now()

        val savedAward = runXpAwardRepository.save(
            RunXpAward(
                id = idGenerator.generate(),
                userId = userId,
                sessionId = sessionId,
                baseXp = baseXp,
                bonusType = bonusDecision.type,
                bonusMultiplier = bonusDecision.multiplier,
                bonusXp = bonusXp,
                totalXpAwarded = totalXpAwarded,
                awardedAt = now,
            )
        )

        val updatedExerciseLevel = if (bonusXp > 0L) {
            exerciseLevelRepository.addXp(userId, ExerciseType.JOGGING, bonusXp)
        } else {
            exerciseLevelRepository.get(userId, ExerciseType.JOGGING)
        }

        return AwardSocialRunXpResult(
            award = savedAward,
            appliedBonusXp = bonusXp,
            updatedExerciseLevel = updatedExerciseLevel,
            updatedUserLevel = levelRepository.getOrCreate(userId),
        )
    }
}
