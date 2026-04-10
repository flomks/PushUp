package com.sinura.data.api.engine

import io.ktor.client.engine.HttpClientEngine
import io.ktor.client.engine.cio.CIO

/**
 * JVM/Desktop implementation: CIO (Coroutine-based I/O) engine.
 *
 * CIO is a pure-Kotlin, coroutine-native HTTP engine with no external
 * native dependencies. It is the recommended choice for JVM targets
 * in KMP projects where OkHttp is not available.
 */
actual fun createHttpClientEngine(): HttpClientEngine = CIO.create()
