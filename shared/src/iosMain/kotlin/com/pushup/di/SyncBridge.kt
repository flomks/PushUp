package com.pushup.di

import com.pushup.domain.usecase.sync.SyncManager
import com.pushup.domain.usecase.sync.SyncResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.koin.core.component.KoinComponent
import org.koin.core.component.get

/**
 * iOS-facing bridge that exposes [SyncManager] operations to Swift.
 *
 * Sync work runs on [Dispatchers.Default] to keep the main thread free.
 * All callbacks are dispatched back on [Dispatchers.Main] so Swift can update
 * `@Published` properties directly without `DispatchQueue.main.async`.
 *
 * ## Usage from Swift
 * ```swift
 * SyncBridge.shared.syncAll(
 *     onSuccess: { SyncService.shared.handleSyncSuccess() },
 *     onError:   { msg in SyncService.shared.handleSyncError(msg) }
 * )
 * ```
 */
object SyncBridge : KoinComponent {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private fun collectErrors(result: SyncResult.Completed): String =
        listOfNotNull(
            result.workoutsError?.message,
            result.joggingError?.message,
            result.timeCreditError?.message,
            result.levelError?.message,
            result.exerciseLevelsError?.message,
            result.fromCloudError?.message,
        ).joinToString("; ")

    // =========================================================================
    // Full sync (upload pending + pull from cloud)
    // =========================================================================

    /**
     * Runs a full sync cycle: uploads pending local data, then pulls the
     * latest state from Supabase.
     *
     * Calls [onSuccess] with a human-readable summary on completion.
     * Calls [onError] with a user-facing message if the sync fails entirely.
     * Partial failures (e.g. one use-case fails but others succeed) are
     * reported via [onSuccess] with a non-empty [errorSummary].
     */
    fun syncAll(
        onSuccess: (errorSummary: String) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val result = get<SyncManager>().syncAll()
                when (result) {
                    is SyncResult.Skipped -> withContext(Dispatchers.Main) { onError(result.reason) }
                    is SyncResult.Completed -> {
                        withContext(Dispatchers.Main) { onSuccess(collectErrors(result)) }
                    }
                }
            } catch (e: Exception) {
                val msg = e.message ?: "Sync failed"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }

    // =========================================================================
    // Post-login pull (restore cloud data on a new device / after logout)
    // =========================================================================

    /**
     * Pulls all data from Supabase into the local database.
     *
     * Call this immediately after a successful login to restore the user's
     * workout history, time credits, and other cloud data locally.
     *
     * Calls [onSuccess] when the pull completes (even if partially).
     * Calls [onError] with a user-facing message if the pull fails entirely.
     */
    fun syncFromCloud(
        onSuccess: () -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val result = get<SyncManager>().syncFromCloud()
                when (result) {
                    is SyncResult.Skipped -> withContext(Dispatchers.Main) { onSuccess() }
                    is SyncResult.Completed -> withContext(Dispatchers.Main) { onSuccess() }
                }
            } catch (e: Exception) {
                val msg = e.message ?: "Cloud sync failed"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }

    // =========================================================================
    // Post-workout upload
    // =========================================================================

    /**
     * Uploads pending workout sessions and time credits immediately after a
     * workout is finished. Skips the full cloud pull to keep the flow fast.
     *
     * Calls [onSuccess] on completion, [onError] on failure.
     */
    fun syncAfterWorkout(
        onSuccess: () -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                when (val result = get<SyncManager>().syncAfterWorkout()) {
                    is SyncResult.Skipped -> {
                        withContext(Dispatchers.Main) { onError(result.reason) }
                    }
                    is SyncResult.Completed -> {
                        val errors = collectErrors(result)
                        if (errors.isBlank()) {
                            withContext(Dispatchers.Main) { onSuccess() }
                        } else {
                            withContext(Dispatchers.Main) { onError(errors) }
                        }
                    }
                }
            } catch (e: Exception) {
                val msg = e.message ?: "Post-workout sync failed"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }
}
