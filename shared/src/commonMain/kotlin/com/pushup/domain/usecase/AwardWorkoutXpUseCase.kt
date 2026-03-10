package com.pushup.domain.usecase

import com.pushup.domain.model.LevelCalculator
import com.pushup.domain.model.UserLevel
import com.pushup.domain.repository.LevelRepository

/**
 * Use-case: Award XP to a user for completing a workout session.
 *
 * XP is calculated from the push-up count and session quality using
 * [LevelCalculator.calculateXp]:
 *   - Base: [LevelCalculator.BASE_XP_PER_PUSHUP] XP per push-up.
 *   - Quality multiplier: 1.5x (excellent), 1.0x (good), 0.7x (poor).
 *
 * If the calculated XP is 0 (e.g. 0 push-ups), no update is made and the
 * current level is returned unchanged.
 *
 * @property levelRepository Repository used to persist and retrieve XP data.
 */
class AwardWorkoutXpUseCase(
    private val levelRepository: LevelRepository,
) {

    /**
     * Awards XP for a completed workout and returns the updated [UserLevel].
     *
     * @param userId      The ID of the user to award XP to.
     * @param pushUpCount Number of push-ups completed (must be >= 0).
     * @param quality     Session quality score in [0.0, 1.0].
     * @return The updated [UserLevel] after XP has been applied.
     */
    suspend operator fun invoke(
        userId: String,
        pushUpCount: Int,
        quality: Float,
    ): UserLevel {
        require(userId.isNotBlank()) { "userId must not be blank" }
        require(pushUpCount >= 0) { "pushUpCount must be >= 0, was $pushUpCount" }
        require(quality in 0f..1f) { "quality must be in [0, 1], was $quality" }

        val xpEarned = LevelCalculator.calculateXp(pushUpCount, quality)
        if (xpEarned == 0L) {
            return levelRepository.getOrCreate(userId)
        }
        return levelRepository.addXp(userId, xpEarned)
    }
}
