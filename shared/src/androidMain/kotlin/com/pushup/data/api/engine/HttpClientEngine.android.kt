package com.pushup.data.api.engine

import io.ktor.client.engine.HttpClientEngine
import io.ktor.client.engine.okhttp.OkHttp

/**
 * Android implementation: OkHttp engine.
 *
 * OkHttp is the de-facto standard HTTP client on Android, offering
 * connection pooling, transparent GZIP, and robust TLS support.
 */
actual fun createHttpClientEngine(): HttpClientEngine = OkHttp.create()
