package com.sinura.data.api

import com.sinura.data.api.engine.createHttpClientEngine
import io.ktor.client.HttpClient
import io.ktor.client.engine.HttpClientEngine
import io.ktor.client.plugins.HttpRequestRetry
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.logging.LogLevel
import io.ktor.client.plugins.logging.Logger
import io.ktor.client.plugins.logging.Logging
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

/**
 * Creates a fully configured [HttpClient] for use by [SupabaseClient] and [KtorApiClient].
 *
 * The client is configured with:
 * - **JSON content negotiation** via `kotlinx.serialization` (lenient, ignores unknown keys).
 * - **Logging** at [LogLevel.HEADERS] in debug builds, [LogLevel.NONE] in release.
 *   Sensitive headers (`Authorization`, `apikey`) are sanitised in logs.
 * - **Retry** (installed first, as required when combined with [HttpTimeout]):
 *   retries on network errors, timeouts, and 503 responses up to 3 times with
 *   exponential back-off.
 * - **Timeouts**: 30s connect, 60s request/socket.
 *
 * @param engine  The platform-specific [HttpClientEngine] to use. Defaults to
 *                the result of [createHttpClientEngine] (expect/actual).
 * @param isDebug When `true`, HTTP headers are logged. Set to `false` in production
 *                to avoid leaking sensitive data (JWT tokens, API keys) into logs.
 */
fun createHttpClient(
    engine: HttpClientEngine = createHttpClientEngine(),
    isDebug: Boolean = false,
): HttpClient = HttpClient(engine) {

    // -------------------------------------------------------------------------
    // Retry -- must be installed BEFORE HttpTimeout (Ktor requirement)
    // -------------------------------------------------------------------------
    install(HttpRequestRetry) {
        // Retry on network-level exceptions (connection refused, DNS failure, etc.)
        retryOnException(maxRetries = 3, retryOnTimeout = true)
        // Retry on 503 Service Unavailable
        retryIf(maxRetries = 3) { _, response ->
            response.status == HttpStatusCode.ServiceUnavailable
        }
        // Exponential back-off with default parameters (base=2, initial=1s, max=64s)
        exponentialDelay()
    }

    // -------------------------------------------------------------------------
    // Timeouts
    // -------------------------------------------------------------------------
    install(HttpTimeout) {
        connectTimeoutMillis = 30_000   // 30 seconds to establish a connection
        requestTimeoutMillis = 60_000   // 60 seconds for the full request/response cycle
        socketTimeoutMillis  = 60_000   // 60 seconds of socket inactivity
    }

    // -------------------------------------------------------------------------
    // JSON content negotiation
    // -------------------------------------------------------------------------
    install(ContentNegotiation) {
        json(
            Json {
                // Ignore unknown JSON keys -- forward-compatible with server additions
                ignoreUnknownKeys = true
                // Lenient parsing for resilience against minor format variations
                isLenient = true
                // Do not encode default values -- keeps PATCH payloads minimal
                encodeDefaults = false
                // Pretty-print in debug mode for easier log reading
                prettyPrint = isDebug
            }
        )
    }

    // -------------------------------------------------------------------------
    // Logging
    // -------------------------------------------------------------------------
    install(Logging) {
        logger = object : Logger {
            override fun log(message: String) {
                // Route to platform logger in a real app. println keeps the
                // shared module free of platform-specific logging dependencies.
                println("[KtorClient] $message")
            }
        }
        level = if (isDebug) LogLevel.HEADERS else LogLevel.NONE
        // Sanitise sensitive headers so tokens never appear in logs
        sanitizeHeader { header -> header == "Authorization" || header == "apikey" }
    }
}
