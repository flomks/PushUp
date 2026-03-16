package com.pushup.plugins

import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.application.log
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.plugins.calllogging.processingTimeMillis
import io.ktor.server.plugins.defaultheaders.DefaultHeaders
import io.ktor.server.request.httpMethod
import io.ktor.server.request.path
import org.slf4j.event.Level

fun Application.configureMonitoring() {
    // Set SUPPRESS_HEALTH_LOG=true in .env to hide /health from logs.
    // By default ALL requests are logged so you can always see what is
    // reaching the server. Only suppress once you have confirmed
    // everything works and the healthcheck noise bothers you.
    val suppressHealth = System.getenv("SUPPRESS_HEALTH_LOG")?.lowercase() == "true"

    install(CallLogging) {
        level = Level.INFO

        if (suppressHealth) {
            filter { call -> !call.request.path().startsWith("/health") }
        }

        // Custom log format: shows method, path, status code, and duration.
        // Example: "200 OK: GET /api/stats/daily (12ms)"
        format { call ->
            val status = call.response.status() ?: HttpStatusCode(0, "Unknown")
            val method = call.request.httpMethod.value
            val path = call.request.path()
            val duration = call.processingTimeMillis()
            "$status: $method $path (${duration}ms)"
        }
    }

    install(DefaultHeaders) {
        header("X-Content-Type-Options", "nosniff")
        header("X-Frame-Options", "DENY")
        header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        // Allow inline styles for the /friend/<code> landing page HTML.
        // All other responses are JSON so this has no security impact on them.
        header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; img-src data:")
        header("Referrer-Policy", "no-referrer")
        header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
    }

    log.info(
        "Monitoring configured (call logging: enabled, /health logging: {})",
        if (suppressHealth) "suppressed (SUPPRESS_HEALTH_LOG=true)" else "enabled",
    )
}
