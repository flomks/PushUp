package com.pushup.domain.usecase.sync

import kotlinx.cinterop.ExperimentalForeignApi
import platform.Network.nw_path_get_status
import platform.Network.nw_path_monitor_cancel
import platform.Network.nw_path_monitor_create
import platform.Network.nw_path_monitor_set_queue
import platform.Network.nw_path_monitor_set_update_handler
import platform.Network.nw_path_monitor_start
import platform.Network.nw_path_monitor_t
import platform.Network.nw_path_status_satisfied
import platform.darwin.DISPATCH_QUEUE_PRIORITY_DEFAULT
import platform.darwin.dispatch_get_global_queue

/**
 * iOS implementation of [NetworkMonitor] backed by the Network framework's
 * `nw_path_monitor` C API.
 *
 * The monitor is started on a background dispatch queue and caches the latest
 * path status in [connected]. [isConnected] reads the cached value
 * synchronously, making it safe to call from any coroutine context without
 * blocking the main thread.
 *
 * **Lifecycle**: The monitor handle is retained as a property so that ARC does
 * not release it immediately after [init] returns. Call [cancel] to stop the
 * monitor and release the underlying native resource when it is no longer
 * needed (e.g. in a Koin `onClose` block or application teardown).
 *
 * **Optimistic default**: [connected] starts as `true` so that the first sync
 * attempt is not skipped before the monitor delivers its initial path update
 * (which typically arrives within milliseconds of [init]).
 *
 * Available from iOS 12.0 onwards.
 */
@OptIn(ExperimentalForeignApi::class)
class IosNetworkMonitor : NetworkMonitor {

    /**
     * Retained handle to the underlying `nw_path_monitor_t`.
     *
     * Must be stored as a property — if it were a local variable in [init],
     * ARC would release it immediately after the block exits, silently
     * stopping the update handler from ever firing.
     */
    private val monitor: nw_path_monitor_t = nw_path_monitor_create()

    /**
     * Cached connectivity status. Updated on the background dispatch queue
     * by the path monitor's update handler.
     *
     * Defaults to `true` (optimistic) so that the first sync attempt is not
     * skipped before the monitor delivers its initial path update.
     */
    @Volatile
    private var connected: Boolean = true

    init {
        nw_path_monitor_set_update_handler(monitor) { path ->
            connected = nw_path_get_status(path) == nw_path_status_satisfied
        }
        nw_path_monitor_set_queue(
            monitor,
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT.toLong(), 0u),
        )
        nw_path_monitor_start(monitor)
    }

    override suspend fun isConnected(): Boolean = connected

    /**
     * Stops the path monitor and releases the underlying native resource.
     *
     * After calling [cancel], [isConnected] will continue to return the last
     * cached value but will no longer be updated. This method is idempotent.
     *
     * Call this when the monitor is no longer needed (e.g. in a Koin
     * `onClose` block):
     * ```kotlin
     * single<NetworkMonitor>(named(NETWORK_MONITOR)) {
     *     IosNetworkMonitor()
     * } onClose {
     *     (it as? IosNetworkMonitor)?.cancel()
     * }
     * ```
     */
    fun cancel() {
        nw_path_monitor_cancel(monitor)
    }
}
