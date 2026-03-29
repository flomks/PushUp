package com.pushup.domain.usecase.sync

import com.pushup.data.api.ApiException
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.UpsertExerciseLevelRequest
import com.pushup.data.api.isTransient
import com.pushup.domain.model.ExerciseType
import com.pushup.domain.repository.ExerciseLevelRepository
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay

/**
 * Use-case: Synchronise all per-exercise [ExerciseLevel] records with Supabase.
 *
 * ## Strategy
 * For each [ExerciseType], applies the same "Highest XP Wins" conflict
 * resolution as [SyncLevelUseCase]:
 * - Local XP > remote XP  -> push local to remote.
 * - Remote XP > local XP  -> pull diff into local.
 * - No local record       -> pull from remote if available.
 * - No remote record      -> push local to remote.
 *
 * All six exercise types are synced in a single invocation.
 *
 * @property exerciseLevelRepository Local repository for per-exercise XP data.
 * @property supabaseClient         Remote API client for Supabase PostgREST.
 * @property networkMonitor          Checks whether the device has internet connectivity.
 * @property maxRetries              Maximum retry attempts (default 3).
 * @property baseDelayMs             Base delay in ms for exponential back-off (default 500).
 */
class SyncExerciseLevelsUseCase(
    private val exerciseLevelRepository: ExerciseLevelRepository,
    private val supabaseClient: CloudSyncApi,
    private val networkMonitor: NetworkMonitor,
    private val maxRetries: Int = 3,
    private val baseDelayMs: Long = 500L,
) {

    /**
     * Syncs all exercise-level records for [userId].
     *
     * @return A [SyncExerciseLevelsResult] describing the overall outcome.
     */
    suspend operator fun invoke(userId: String): SyncExerciseLevelsResult {
        require(userId.isNotBlank()) { "userId must not be blank" }

        if (!networkMonitor.isConnected()) {
            throw SyncException.NoNetwork("Cannot sync exercise levels: no internet connection")
        }

        return syncWithRetry(userId)
    }

    private suspend fun syncWithRetry(userId: String): SyncExerciseLevelsResult {
        var lastException: Exception? = null

        repeat(maxRetries) { attempt ->
            try {
                return doSync(userId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiException) {
                if (!e.isTransient) {
                    return SyncExerciseLevelsResult.Failed(e)
                }
                lastException = e
                delay(baseDelayMs * (1L shl attempt))
            } catch (e: Exception) {
                lastException = e
                delay(baseDelayMs * (1L shl attempt))
            }
        }

        return SyncExerciseLevelsResult.Failed(
            lastException ?: Exception("All retries exhausted"),
        )
    }

    private suspend fun doSync(userId: String): SyncExerciseLevelsResult {
        val remoteList = supabaseClient.getExerciseLevels(userId)
        val remoteByType = remoteList.associateBy { it.exerciseType }

        var pushed = 0
        var pulled = 0

        for (type in ExerciseType.entries) {
            val local = exerciseLevelRepository.get(userId, type)
            val remote = remoteByType[type]

            when {
                local == null && remote != null -> {
                    exerciseLevelRepository.addXp(userId, type, remote.totalXp)
                    pulled++
                }

                local != null && remote == null -> {
                    if (local.totalXp > 0) {
                        supabaseClient.upsertExerciseLevel(
                            userId = userId,
                            request = UpsertExerciseLevelRequest(
                                userId = userId,
                                exerciseType = type.id,
                                totalXp = local.totalXp,
                            ),
                        )
                        pushed++
                    }
                }

                local != null && remote != null -> {
                    when {
                        local.totalXp > remote.totalXp -> {
                            supabaseClient.upsertExerciseLevel(
                                userId = userId,
                                request = UpsertExerciseLevelRequest(
                                    userId = userId,
                                    exerciseType = type.id,
                                    totalXp = local.totalXp,
                                ),
                            )
                            pushed++
                        }

                        remote.totalXp > local.totalXp -> {
                            val diff = remote.totalXp - local.totalXp
                            exerciseLevelRepository.addXp(userId, type, diff)
                            pulled++
                        }
                    }
                }
            }
        }

        return when {
            pushed > 0 || pulled > 0 -> SyncExerciseLevelsResult.Synced(pushed, pulled)
            else -> SyncExerciseLevelsResult.AlreadySynced
        }
    }
}

// =============================================================================
// Result type
// =============================================================================

sealed class SyncExerciseLevelsResult {

    /** One or more exercise levels were synced (pushed and/or pulled). */
    data class Synced(val pushed: Int, val pulled: Int) : SyncExerciseLevelsResult()

    /** All exercise levels were already in sync. */
    data object AlreadySynced : SyncExerciseLevelsResult()

    /** The sync failed after all retry attempts. */
    data class Failed(val cause: Exception) : SyncExerciseLevelsResult()
}
