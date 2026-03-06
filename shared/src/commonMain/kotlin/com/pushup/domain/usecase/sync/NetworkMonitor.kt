package com.pushup.domain.usecase.sync

/**
 * Abstraction over platform-specific network connectivity detection.
 *
 * Implementations are platform-specific (Android ConnectivityManager,
 * iOS NWPathMonitor, JVM socket probe) and are bound in the platform
 * DI modules. Tests use [AlwaysConnectedNetworkMonitor] or
 * [AlwaysOfflineNetworkMonitor] for deterministic behaviour.
 *
 * The sync use-cases call [isConnected] before every sync attempt so that
 * no network requests are made when the device is offline.
 */
fun interface NetworkMonitor {

    /**
     * Returns `true` when the device currently has a usable internet connection.
     *
     * This is a **snapshot** check -- it does not observe connectivity changes.
     * Callers that need reactive connectivity should observe a [kotlinx.coroutines.flow.Flow]
     * at a higher layer (e.g. in the ViewModel or SyncManager scheduler).
     */
    suspend fun isConnected(): Boolean
}

// =============================================================================
// Convenience implementations for tests and previews
// =============================================================================

/**
 * [NetworkMonitor] that always reports the device as connected.
 *
 * Use in unit tests to exercise the "online" code path without a real network.
 */
object AlwaysConnectedNetworkMonitor : NetworkMonitor {
    override suspend fun isConnected(): Boolean = true
}

/**
 * [NetworkMonitor] that always reports the device as offline.
 *
 * Use in unit tests to verify that sync is skipped when there is no connection.
 */
object AlwaysOfflineNetworkMonitor : NetworkMonitor {
    override suspend fun isConnected(): Boolean = false
}
