package com.sinura.data.api.engine

import io.ktor.client.engine.HttpClientEngine

/**
 * Platform-specific [HttpClientEngine] factory.
 *
 * Each platform provides its own actual implementation:
 * - **Android**: OkHttp engine (robust, battle-tested on Android)
 * - **iOS**: Darwin engine (native NSURLSession, no extra dependencies)
 * - **JVM/Desktop**: CIO engine (pure Kotlin, coroutine-based)
 *
 * The engine is created once and shared across all [io.ktor.client.HttpClient]
 * instances via the Koin DI graph.
 */
expect fun createHttpClientEngine(): HttpClientEngine
