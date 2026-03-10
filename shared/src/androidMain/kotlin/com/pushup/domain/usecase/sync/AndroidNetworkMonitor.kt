package com.pushup.domain.usecase.sync

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities

/**
 * Android implementation of [NetworkMonitor] backed by [ConnectivityManager].
 *
 * Uses [NetworkCapabilities] (API 23+) to check whether the active network
 * has internet capability. This is a snapshot check -- it does not observe
 * connectivity changes reactively.
 *
 * Requires the `android.permission.ACCESS_NETWORK_STATE` permission in
 * AndroidManifest.xml.
 *
 * @param context Application [Context] used to obtain the [ConnectivityManager].
 */
class AndroidNetworkMonitor(private val context: Context) : NetworkMonitor {

    override suspend fun isConnected(): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }
}
