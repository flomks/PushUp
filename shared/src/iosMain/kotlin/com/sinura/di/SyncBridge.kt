package com.sinura.di

import com.sinura.domain.usecase.sync.SyncManager
import com.sinura.domain.usecase.sync.SyncResult
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
            result.workouts?.takeIf { it.failed > 0 }?.let { "Workout sync failed for ${it.failed} session(s)" },
            result.jogging?.takeIf { it.failed > 0 }?.let { "Jogging sync failed for ${it.failed} session(s)" },
            result.timeCredit.takeFailureMessage(),
            result.level.takeFailureMessage(),
            result.exerciseLevels.takeFailureMessage(),
            result.fromCloud?.takeIf { !it.isFullSuccess }?.let {
                "Cloud pull partial failure: sessionsFailed=${it.sessionsFailed}"
            },
            result.workoutsError?.message,
            result.joggingError?.message,
            result.timeCreditError?.message,
            result.levelError?.message,
            result.exerciseLevelsError?.message,
            result.fromCloudError?.message,
        ).filter { it.isNotBlank() }
            .distinct()
            .joinToString("; ")

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
            append(
                when (result.timeCredit) {
                    null -> "not-run"
                    is com.sinura.domain.usecase.sync.SyncTimeCreditResult.Synced -> "synced"
                    is com.sinura.domain.usecase.sync.SyncTimeCreditResult.NoLocalData -> "no-local-data"
                    is com.sinura.domain.usecase.sync.SyncTimeCreditResult.AlreadySynced -> "already-synced"
                    is com.sinura.domain.usecase.sync.SyncTimeCreditResult.PulledFromRemote -> "pulled-from-remote"
                    is com.sinura.domain.usecase.sync.SyncTimeCreditResult.Failed -> "failed"
                },
            )
            append(" level=")
            append(
                when (val level = result.level) {
                    null -> "not-run"
                    is com.sinura.domain.usecase.sync.SyncLevelResult.Synced -> "synced"
                    is com.sinura.domain.usecase.sync.SyncLevelResult.AlreadySynced -> "already-synced"
                    is com.sinura.domain.usecase.sync.SyncLevelResult.NoLocalData -> "no-local-data"
                    is com.sinura.domain.usecase.sync.SyncLevelResult.PulledFromRemote -> "pulled-from-remote:${level.remote.totalXp}"
                    is com.sinura.domain.usecase.sync.SyncLevelResult.Failed -> "failed"
                },
            )
            append(" exerciseLevels=")
            append(
                when (val exerciseLevels = result.exerciseLevels) {
                    null -> "not-run"
                    is com.sinura.domain.usecase.sync.SyncExerciseLevelsResult.Synced ->
                        "synced:pushed=${exerciseLevels.pushed},pulled=${exerciseLevels.pulled}"
                    is com.sinura.domain.usecase.sync.SyncExerciseLevelsResult.AlreadySynced -> "already-synced"
                    is com.sinura.domain.usecase.sync.SyncExerciseLevelsResult.Failed -> "failed"
                },
            )
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

private fun com.sinura.domain.usecase.sync.SyncTimeCreditResult?.takeFailureMessage(): String? =
    when (this) {
        is com.sinura.domain.usecase.sync.SyncTimeCreditResult.Failed -> cause.message ?: "Time credit sync failed"
        else -> null
    }

private fun com.sinura.domain.usecase.sync.SyncLevelResult?.takeFailureMessage(): String? =
    when (this) {
        is com.sinura.domain.usecase.sync.SyncLevelResult.Failed -> cause.message ?: "Level sync failed"
        else -> null
    }

private fun com.sinura.domain.usecase.sync.SyncExerciseLevelsResult?.takeFailureMessage(): String? =
    when (this) {
        is com.sinura.domain.usecase.sync.SyncExerciseLevelsResult.Failed -> cause.message ?: "Exercise level sync failed"
        else -> null
    }
