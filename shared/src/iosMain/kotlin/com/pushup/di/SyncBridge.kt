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

    private fun log(message: String) {
        println("[SyncBridge] $message")
    }

    private fun collectErrors(result: SyncResult.Completed): String =
        listOfNotNull(
            result.workoutsError?.message,
            result.joggingError?.message,
            result.timeCreditError?.message,
            result.levelError?.message,
            result.exerciseLevelsError?.message,
            result.fromCloudError?.message,
        ).joinToString("; ")

    private fun summarize(result: SyncResult.Completed): String =
        buildString {
            append("workouts=")
            append(
                result.workouts?.let { "synced=${it.synced},skipped=${it.skipped},failed=${it.failed}" }
                    ?: "not-run",
            )
            append(" jogging=")
            append(
                result.jogging?.let { "synced=${it.synced},skipped=${it.skipped},failed=${it.failed}" }
                    ?: "not-run",
            )
            append(" timeCredit=")
            append(result.timeCredit?.javaClass?.simpleName ?: "not-run")
            append(" level=")
            append(result.level?.javaClass?.simpleName ?: "not-run")
            append(" exerciseLevels=")
            append(result.exerciseLevels?.javaClass?.simpleName ?: "not-run")
            append(" fromCloud=")
            append(result.fromCloud?.let { "downloaded=${it.sessionsDownloaded},updated=${it.sessionsInsertedOrUpdated}" } ?: "not-run")
        }

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
                log("syncAll requested from iOS")
                val result = get<SyncManager>().syncAll()
                when (result) {
                    is SyncResult.Skipped -> {
                        log("syncAll skipped: ${result.reason}")
                        withContext(Dispatchers.Main) { onError(result.reason) }
                    }
                    is SyncResult.Completed -> {
                        val errors = collectErrors(result)
                        log("syncAll completed: ${summarize(result)} errors=${if (errors.isBlank()) "<none>" else errors}")
                        withContext(Dispatchers.Main) { onSuccess(collectErrors(result)) }
                    }
                }
            } catch (e: Exception) {
                val msg = e.message ?: "Sync failed"
                log("syncAll crashed: $msg")
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
                log("syncFromCloud requested from iOS")
                val result = get<SyncManager>().syncFromCloud()
                when (result) {
                    is SyncResult.Skipped -> {
                        log("syncFromCloud skipped: ${result.reason}")
                        withContext(Dispatchers.Main) { onSuccess() }
                    }
                    is SyncResult.Completed -> {
                        log("syncFromCloud completed: ${summarize(result)} errors=${collectErrors(result)}")
                        withContext(Dispatchers.Main) { onSuccess() }
                    }
                }
            } catch (e: Exception) {
                val msg = e.message ?: "Cloud sync failed"
                log("syncFromCloud crashed: $msg")
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
                log("syncAfterWorkout requested from iOS")
                when (val result = get<SyncManager>().syncAfterWorkout()) {
                    is SyncResult.Skipped -> {
                        log("syncAfterWorkout skipped: ${result.reason}")
                        withContext(Dispatchers.Main) { onError(result.reason) }
                    }
                    is SyncResult.Completed -> {
                        val errors = collectErrors(result)
                        log("syncAfterWorkout completed: ${summarize(result)} errors=${if (errors.isBlank()) "<none>" else errors}")
                        if (errors.isBlank()) {
                            withContext(Dispatchers.Main) { onSuccess() }
                        } else {
                            withContext(Dispatchers.Main) { onError(errors) }
                        }
                    }
                }
            } catch (e: Exception) {
                val msg = e.message ?: "Post-workout sync failed"
                log("syncAfterWorkout crashed: $msg")
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }
}
