package com.sinura.domain.usecase

import com.sinura.domain.model.UserLevel
import com.sinura.domain.repository.LevelRepository

/**
 * Use-case: Retrieve the current XP / level state for a user.
 *
 * Returns the existing [UserLevel] if one exists, or an initial level-1 record
 * if the user has never earned any XP yet.
 *
 * @property levelRepository Repository used to read and initialise level data.
 */
class GetUserLevelUseCase(
    private val levelRepository: LevelRepository,
) {

    /**
     * Returns the [UserLevel] for [userId], creating an initial record if needed.
     *
     * @param userId The ID of the user whose level to retrieve.
     * @return The current [UserLevel] (never null -- initialised to level 1 on first call).
     */
    suspend operator fun invoke(userId: String): UserLevel {
        require(userId.isNotBlank()) { "userId must not be blank" }
        return levelRepository.getOrCreate(userId)
    }
}
