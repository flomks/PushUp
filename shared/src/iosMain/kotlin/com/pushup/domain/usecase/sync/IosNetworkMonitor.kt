package com.pushup.domain.usecase.sync

import kotlinx.cinterop.ExperimentalForeignApi
import platform.Network.nw_path_get_status
import platform.Network.nw_path_monitor_cancel
import platform.Network.nw_path_monitor_create
import platform.Network.nw_path_monitor_set_queue
import platform.Network.nw_path_monitor_set_update_handler
import platform.Network.nw_path_monitor_start
import platform.Network.nw_path_status_satisfied
import platform.darwin.DISPATCH_QUEUE_PRIORITY_DEFAULT
import platform.darwin.dispatch_get_global_queue

/**
 * iOS implementation of [NetworkMonitor] backed by the Network framework's
 * `nw_path_monitor` C API.
 *
 * The monitor is started on a background dispatch queue and caches the
 * latest path status. [isConnected] reads the cached status synchronously,
 * making it safe to call from a coroutine without blocking the main thread.
 *
 * The monitor is started lazily on first access and runs for the lifetime
 * of the application (it is bound as a Koin singleton).
 *
 * Available from iOS 12.0 onwards.
 */
@OptIn(ExperimentalForeignApi::class)
class IosNetworkMonitor : NetworkMonitor {

    /**
     * Cached connectivity status. Defaults to `true` (optimistic) so that
     * the first sync attempt is not skipped before the monitor delivers its
     * first path update.
     */
    @Volatile
    private var connected: Boolean = true

    init {
        val monitor = nw_path_monitor_create()
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
}
