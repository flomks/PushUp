package com.pushup.data.api.engine

import io.ktor.client.engine.HttpClientEngine
import io.ktor.client.engine.darwin.Darwin

/**
 * iOS implementation: Darwin engine (NSURLSession).
 *
 * The Darwin engine delegates all HTTP work to Apple's native
 * NSURLSession, which means it respects system proxy settings,
 * certificate pinning, and App Transport Security (ATS) out of the box.
 * No additional native dependencies are required.
 */
actual fun createHttpClientEngine(): HttpClientEngine = Darwin.create()
