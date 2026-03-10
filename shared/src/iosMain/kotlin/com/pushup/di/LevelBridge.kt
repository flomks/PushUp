package com.pushup.di

import com.pushup.domain.usecase.GetUserLevelUseCase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.koin.core.component.KoinComponent
import org.koin.core.component.get

/**
 * iOS-facing bridge that exposes the XP / level system to Swift.
 *
 * All suspend work runs on [Dispatchers.Default] to keep the main thread free.
 * Callbacks are dispatched back on [Dispatchers.Main] so Swift ViewModels can
 * update @Published properties directly without DispatchQueue.main.async.
 */
object LevelBridge : KoinComponent {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /**
     * Fetches the current XP / level state for [userId].
     *
     * Creates an initial level-1 record if the user has never earned XP yet,
     * so [onResult] is always called with a valid [LevelResult] (never null).
     *
     * @param userId   The authenticated user's ID.
     * @param onResult Called on the main thread with the current [LevelResult].
     * @param onError  Called on the main thread with a user-facing error message.
     */
    fun getUserLevel(
        userId: String,
        onResult: (LevelResult) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val userLevel = get<GetUserLevelUseCase>().invoke(userId)
                val result = LevelResult(
                    level = userLevel.level,
                    totalXp = userLevel.totalXp,
                    xpIntoLevel = userLevel.xpIntoLevel,
                    xpRequiredForNextLevel = userLevel.xpRequiredForNextLevel,
                    levelProgress = userLevel.levelProgress.toDouble(),
                )
                withContext(Dispatchers.Main) { onResult(result) }
            } catch (e: Exception) {
                val msg = "Could not load level: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }
}

// =============================================================================
// Plain data transfer object — no Kotlin generics, safe for Swift export
// =============================================================================

/**
 * XP / level state returned by [LevelBridge.getUserLevel].
 *
 * All numeric types are chosen to be directly usable in Swift without casting:
 * - [level] as Int (Swift Int)
 * - [totalXp] / [xpIntoLevel] / [xpRequiredForNextLevel] as Long (Swift Int64)
 * - [levelProgress] as Double (Swift Double) in [0.0, 1.0)
 */
data class LevelResult(
    /** Current level (1-based). */
    val level: Int,
    /** Total XP accumulated across all time. */
    val totalXp: Long,
    /** XP accumulated within the current level. */
    val xpIntoLevel: Long,
    /** XP needed to advance to the next level. */
    val xpRequiredForNextLevel: Long,
    /** Progress fraction within the current level, in [0.0, 1.0). */
    val levelProgress: Double,
)
