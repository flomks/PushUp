package com.pushup.domain.usecase.sync

import com.pushup.domain.repository.AuthRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Orchestrates all sync operations for the authenticated user.
 *
 * [SyncManager] is the single entry point for triggering synchronisation.
 * It coordinates [SyncWorkoutsUseCase], [SyncTimeCreditUseCase],
 * [SyncLevelUseCase], and [SyncFromCloudUseCase] in the correct order and
 * handles the common lifecycle concerns:
 *
 * - **Auth check**: reads the current user from [AuthRepository]; skips sync
 *   if no user is authenticated (guest mode).
 * - **Network check**: each individual use-case checks connectivity and throws
 *   [SyncException.NoNetwork] if offline. [SyncManager] catches this via
 *   [runCatching] and surfaces it in the [SyncResult.Completed] error fields.
 * - **Error isolation**: each use-case is wrapped in [runCatching] so that a
 *   failure in one does not prevent the others from running.
 * - **Periodic background sync**: [startPeriodicSync] launches a coroutine that
 *   calls [syncAll] every [periodicIntervalMs] milliseconds. The first execution
 *   fires immediately; subsequent executions are delayed by [periodicIntervalMs].
 * - **Post-workout sync**: [syncAfterWorkout] runs a targeted upload immediately
 *   after a session is finished, without the full pull from cloud.
 *
 * ## Sync order
 * 1. [SyncWorkoutsUseCase] -- upload pending sessions first so the server has
 *    the latest workout data before we pull aggregated stats.
 * 2. [SyncTimeCreditUseCase] -- upload pending credit changes.
 * 3. [SyncLevelUseCase] -- sync XP / level data (highest value wins).
 * 4. [SyncFromCloudUseCase] -- pull the authoritative state from the server.
 *
 * ## Thread safety
 * All public `suspend` functions are safe to call from any coroutine context.
 * The internal [scope] uses [SupervisorJob] so that individual child failures
 * do not propagate upward and cancel the scope.
 *
 * @property syncWorkoutsUseCase   Uploads pending workout sessions.
 * @property syncTimeCreditUseCase Uploads pending time-credit changes.
 * @property syncLevelUseCase      Syncs XP / level data with Supabase.
 * @property syncFromCloudUseCase  Downloads the latest data from Supabase.
 * @property authRepository        Provides the current authenticated user ID.
 * @property scope                 [CoroutineScope] used for periodic sync jobs.
 *   Defaults to a new scope with [SupervisorJob]; override in tests.
 * @property periodicIntervalMs    Interval between periodic background syncs in
 *   milliseconds. Defaults to [DEFAULT_PERIODIC_INTERVAL_MS] (15 minutes).
 */
class SyncManager(
    private val syncWorkoutsUseCase: SyncWorkoutsUseCase,
    private val syncTimeCreditUseCase: SyncTimeCreditUseCase,
    private val syncLevelUseCase: SyncLevelUseCase,
    private val syncFromCloudUseCase: SyncFromCloudUseCase,
    private val authRepository: AuthRepository,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob()),
    val periodicIntervalMs: Long = DEFAULT_PERIODIC_INTERVAL_MS,
) {

    private var periodicSyncJob: Job? = null

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Runs a full sync cycle: upload pending data, then pull from cloud.
     *
     * This is the primary entry point. Call it:
     * - On app start (after the user is authenticated).
     * - After a workout session is finished.
     * - When the app returns to the foreground.
     *
     * @return A [SyncResult] summarising the outcome of all three use-cases.
     *   Returns [SyncResult.Skipped] if the user is not authenticated.
     *   If the device is offline, each use-case will fail with [SyncException.NoNetwork]
     *   which is captured in the corresponding error field of [SyncResult.Completed].
     */
    suspend fun syncAll(): SyncResult {
        val userId = resolveUserId()
            ?: return SyncResult.Skipped(reason = "User not authenticated")

        val workoutsResult = runCatching { syncWorkoutsUseCase(userId) }
        val creditResult = runCatching { syncTimeCreditUseCase(userId) }
        val levelResult = runCatching { syncLevelUseCase(userId) }
        val fromCloudResult = runCatching { syncFromCloudUseCase(userId) }

        return SyncResult.Completed(
            workouts = workoutsResult.getOrNull(),
            workoutsError = workoutsResult.exceptionOrNull(),
            timeCredit = creditResult.getOrNull(),
            timeCreditError = creditResult.exceptionOrNull(),
            level = levelResult.getOrNull(),
            levelError = levelResult.exceptionOrNull(),
            fromCloud = fromCloudResult.getOrNull(),
            fromCloudError = fromCloudResult.exceptionOrNull(),
        )
    }

    /**
     * Runs a targeted sync immediately after a workout session is finished.
     *
     * Only uploads pending sessions and time credits -- skips the full pull
     * to keep the post-workout flow fast. A full [syncAll] will be triggered
     * by the next periodic sync.
     *
     * @return A [SyncResult] summarising the upload outcome.
     *   Returns [SyncResult.Skipped] if the user is not authenticated.
     */
    suspend fun syncAfterWorkout(): SyncResult {
        val userId = resolveUserId()
            ?: return SyncResult.Skipped(reason = "User not authenticated")

        val workoutsResult = runCatching { syncWorkoutsUseCase(userId) }
        val creditResult = runCatching { syncTimeCreditUseCase(userId) }
        val levelResult = runCatching { syncLevelUseCase(userId) }

        return SyncResult.Completed(
            workouts = workoutsResult.getOrNull(),
            workoutsError = workoutsResult.exceptionOrNull(),
            timeCredit = creditResult.getOrNull(),
            timeCreditError = creditResult.exceptionOrNull(),
            level = levelResult.getOrNull(),
            levelError = levelResult.exceptionOrNull(),
            fromCloud = null,
            fromCloudError = null,
        )
    }

    /**
     * Pulls the latest data from Supabase into the local database.
     *
     * Use this after login on a new device to restore all cloud data locally.
     *
     * @return A [SyncResult] summarising the pull outcome.
     *   Returns [SyncResult.Skipped] if the user is not authenticated.
     */
    suspend fun syncFromCloud(): SyncResult {
        val userId = resolveUserId()
            ?: return SyncResult.Skipped(reason = "User not authenticated")

        val levelResult = runCatching { syncLevelUseCase(userId) }
        val fromCloudResult = runCatching { syncFromCloudUseCase(userId) }

        return SyncResult.Completed(
            workouts = null,
            workoutsError = null,
            timeCredit = null,
            timeCreditError = null,
            level = levelResult.getOrNull(),
            levelError = levelResult.exceptionOrNull(),
            fromCloud = fromCloudResult.getOrNull(),
            fromCloudError = fromCloudResult.exceptionOrNull(),
        )
    }

    /**
     * Starts a periodic background sync that calls [syncAll] every [periodicIntervalMs].
     *
     * The first sync fires immediately; subsequent syncs are delayed by [periodicIntervalMs].
     * Calling this method while a periodic sync is already running replaces the
     * existing job with a new one (idempotent restart).
     *
     * The periodic sync runs in [scope]. Cancel [scope] (or call [stopPeriodicSync])
     * to stop it.
     */
    fun startPeriodicSync() {
        periodicSyncJob?.cancel()
        periodicSyncJob = scope.launch {
            while (isActive) {
                runCatching { syncAll() }
                // Errors are swallowed -- the next iteration will retry.
                delay(periodicIntervalMs)
            }
        }
    }

    /**
     * Stops the periodic background sync started by [startPeriodicSync].
     *
     * This is a no-op if no periodic sync is running.
     */
    fun stopPeriodicSync() {
        periodicSyncJob?.cancel()
        periodicSyncJob = null
    }

    /** `true` when a periodic sync job is currently running. */
    val isPeriodicSyncRunning: Boolean
        get() = periodicSyncJob?.isActive == true

    // =========================================================================
    // Private helpers
    // =========================================================================

    private suspend fun resolveUserId(): String? =
        authRepository.getCurrentUser()?.id

    // =========================================================================
    // Constants
    // =========================================================================

    companion object {
        /** Default periodic sync interval: 15 minutes in milliseconds. */
        const val DEFAULT_PERIODIC_INTERVAL_MS: Long = 15 * 60 * 1_000L
    }
}

// =============================================================================
// Result types
// =============================================================================

/**
 * Describes the outcome of a [SyncManager] operation.
 */
sealed class SyncResult {

    /**
     * The sync was skipped because a precondition was not met.
     *
     * @property reason Human-readable explanation (e.g. "User not authenticated").
     */
    data class Skipped(val reason: String) : SyncResult()

    /**
     * The sync completed (possibly with partial failures).
     *
     * Individual use-case results may be `null` if that use-case was not
     * invoked (e.g. [fromCloud] is `null` after [SyncManager.syncAfterWorkout]).
     * An error field being non-null does not prevent the other use-cases from
     * running -- each is isolated via [runCatching].
     *
     * @property workouts       Result of [SyncWorkoutsUseCase], or `null` if not run.
     * @property workoutsError  Exception from [SyncWorkoutsUseCase], or `null` on success.
     * @property timeCredit     Result of [SyncTimeCreditUseCase], or `null` if not run.
     * @property timeCreditError Exception from [SyncTimeCreditUseCase], or `null` on success.
     * @property level          Result of [SyncLevelUseCase], or `null` if not run.
     * @property levelError     Exception from [SyncLevelUseCase], or `null` on success.
     * @property fromCloud      Result of [SyncFromCloudUseCase], or `null` if not run.
     * @property fromCloudError Exception from [SyncFromCloudUseCase], or `null` on success.
     */
    data class Completed(
        val workouts: SyncWorkoutsResult?,
        val workoutsError: Throwable?,
        val timeCredit: SyncTimeCreditResult?,
        val timeCreditError: Throwable?,
        val level: SyncLevelResult?,
        val levelError: Throwable?,
        val fromCloud: SyncFromCloudResult?,
        val fromCloudError: Throwable?,
    ) : SyncResult() {

        /** `true` when all invoked use-cases completed without errors. */
        val isFullSuccess: Boolean
            get() = workoutsError == null &&
                timeCreditError == null &&
                levelError == null &&
                fromCloudError == null &&
                workouts?.isFullSuccess != false &&
                fromCloud?.isFullSuccess != false
    }
}
