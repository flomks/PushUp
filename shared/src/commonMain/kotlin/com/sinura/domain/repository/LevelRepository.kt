package com.sinura.domain.repository

import com.sinura.domain.model.UserLevel

/**
 * Repository for reading and updating a user's XP / level state.
 *
 * The level is derived from [UserLevel.totalXp] using [com.sinura.domain.model.LevelCalculator].
 * Implementations are responsible for persisting [totalXp] and returning a fully
 * computed [UserLevel] on every read.
 */
interface LevelRepository {

    /**
     * Returns the current [UserLevel] for [userId], or `null` if no record exists yet.
     *
     * @param userId The user whose level to retrieve.
     */
    suspend fun get(userId: String): UserLevel?

    /**
     * Adds [xpToAdd] to the user's total XP, creating the record if it does not exist.
     *
     * @param userId   The user to award XP to.
     * @param xpToAdd  Amount of XP to add (must be > 0).
     * @return The updated [UserLevel] after the XP has been applied.
     */
    suspend fun addXp(userId: String, xpToAdd: Long): UserLevel

    /**
     * Returns the current [UserLevel] for [userId], creating an initial record
     * (level 1, 0 XP) if none exists yet.
     *
     * @param userId The user whose level to retrieve or initialise.
     */
    suspend fun getOrCreate(userId: String): UserLevel
}
