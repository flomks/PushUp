package com.pushup.domain.model

import kotlinx.serialization.Serializable
import kotlin.math.floor
import kotlin.math.pow

/**
 * Represents the current XP / level state for a user.
 *
 * @property userId          Identifier of the user this level belongs to.
 * @property totalXp         Total XP accumulated across all time.
 * @property level           Current level (1-based, starts at 1).
 * @property xpIntoLevel     XP accumulated within the current level (0 until [xpRequiredForNextLevel]).
 * @property xpRequiredForNextLevel XP needed to advance from [level] to [level]+1.
 */
@Serializable
data class UserLevel(
    val userId: String,
    val totalXp: Long,
    val level: Int,
    val xpIntoLevel: Long,
    val xpRequiredForNextLevel: Long,
) {
    init {
        require(userId.isNotBlank()) { "UserLevel.userId must not be blank" }
        require(totalXp >= 0) { "UserLevel.totalXp must be >= 0, was $totalXp" }
        require(level >= 1) { "UserLevel.level must be >= 1, was $level" }
        require(xpIntoLevel >= 0) { "UserLevel.xpIntoLevel must be >= 0, was $xpIntoLevel" }
        require(xpRequiredForNextLevel > 0) {
            "UserLevel.xpRequiredForNextLevel must be > 0, was $xpRequiredForNextLevel"
        }
        require(xpIntoLevel < xpRequiredForNextLevel) {
            "UserLevel.xpIntoLevel ($xpIntoLevel) must be < xpRequiredForNextLevel ($xpRequiredForNextLevel)"
        }
    }

    /**
     * Progress fraction within the current level, in [0.0, 1.0).
     *
     * Useful for rendering a progress bar.
     */
    val levelProgress: Float
        get() = xpIntoLevel.toFloat() / xpRequiredForNextLevel.toFloat()

    companion object {
        /**
         * Creates a [UserLevel] for a brand-new user with zero XP.
         */
        fun initial(userId: String): UserLevel = LevelCalculator.fromTotalXp(userId, 0L)
    }
}

/**
 * Pure utility object for XP / level calculations.
 *
 * ## Formula
 * The XP required to complete level `n` (i.e. to advance from level `n` to `n+1`) is:
 *
 *   `xpForLevel(n) = floor(100 * n^1.5)`
 *
 * This gives a smooth exponential curve:
 *   - Level 1 -> 2: 100 XP
 *   - Level 2 -> 3: 283 XP
 *   - Level 5 -> 6: 1118 XP
 *   - Level 10 -> 11: 3162 XP
 *   - Level 20 -> 21: 8944 XP
 *
 * ## XP per push-up
 * Base XP per push-up is **10 XP**.
 *
 * A quality multiplier is applied based on the session's quality score:
 *   - quality > 0.8  -> 1.5x  (excellent form)
 *   - quality >= 0.5 -> 1.0x  (good form)
 *   - quality < 0.5  -> 0.7x  (poor form)
 *
 * This mirrors the time-credit multiplier logic in [FinishWorkoutUseCase].
 */
object LevelCalculator {

    /** Base XP awarded per push-up before any multiplier. */
    const val BASE_XP_PER_PUSHUP: Int = 10

    /**
     * Returns the XP required to advance from level [level] to [level]+1.
     *
     * @param level Current level (must be >= 1).
     */
    fun xpRequiredForLevel(level: Int): Long {
        require(level >= 1) { "level must be >= 1, was $level" }
        return floor(100.0 * level.toDouble().pow(1.5)).toLong()
    }

    /**
     * Returns the total XP required to reach [targetLevel] from level 1 (i.e. from 0 XP).
     *
     * @param targetLevel The level to reach (must be >= 1).
     */
    fun totalXpForLevel(targetLevel: Int): Long {
        require(targetLevel >= 1) { "targetLevel must be >= 1, was $targetLevel" }
        if (targetLevel == 1) return 0L
        return (1 until targetLevel).sumOf { xpRequiredForLevel(it) }
    }

    /**
     * Calculates the XP earned for a workout session.
     *
     * @param pushUpCount Number of push-ups completed.
     * @param quality     Session quality score in [0.0, 1.0].
     * @return XP earned (always >= 0).
     */
    fun calculateXp(pushUpCount: Int, quality: Float): Long {
        require(pushUpCount >= 0) { "pushUpCount must be >= 0, was $pushUpCount" }
        require(quality in 0f..1f) { "quality must be in [0, 1], was $quality" }

        val multiplier: Double = when {
            quality > 0.8f  -> 1.5
            quality >= 0.5f -> 1.0
            else            -> 0.7
        }
        return (pushUpCount * BASE_XP_PER_PUSHUP * multiplier).toLong()
    }

    /**
     * Constructs a [UserLevel] from a raw [totalXp] value by computing the
     * current level and progress within that level.
     *
     * @param userId   The user this level belongs to.
     * @param totalXp  Total accumulated XP (must be >= 0).
     */
    fun fromTotalXp(userId: String, totalXp: Long): UserLevel {
        require(totalXp >= 0) { "totalXp must be >= 0, was $totalXp" }

        val (level, remaining) = deriveLevelAndRemainder(totalXp)

        return UserLevel(
            userId = userId,
            totalXp = totalXp,
            level = level,
            xpIntoLevel = remaining,
            xpRequiredForNextLevel = xpRequiredForLevel(level),
        )
    }

    /**
     * Constructs an [ExerciseLevel] from a raw [totalXp] value for a specific
     * [exerciseType]. Uses the same level curve as [fromTotalXp].
     */
    fun exerciseLevelFromTotalXp(
        userId: String,
        exerciseType: ExerciseType,
        totalXp: Long,
    ): ExerciseLevel {
        require(totalXp >= 0) { "totalXp must be >= 0, was $totalXp" }

        val (level, remaining) = deriveLevelAndRemainder(totalXp)

        return ExerciseLevel(
            userId = userId,
            exerciseType = exerciseType,
            totalXp = totalXp,
            level = level,
            xpIntoLevel = remaining,
            xpRequiredForNextLevel = xpRequiredForLevel(level),
        )
    }

    /**
     * Walks the level curve and returns the (level, xpRemainder) pair for [totalXp].
     */
    private fun deriveLevelAndRemainder(totalXp: Long): Pair<Int, Long> {
        var level = 1
        var remaining = totalXp
        while (true) {
            val needed = xpRequiredForLevel(level)
            if (remaining < needed) break
            remaining -= needed
            level++
        }
        return level to remaining
    }
}
