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
    val isDev = System.getenv("KTOR_ENV") != "production"

    install(CallLogging) {
        level = Level.INFO

        // In production, suppress /health to avoid log flooding from Docker
        // healthchecks (every 30s). In dev, log everything so you can see
        // that the server is alive and responding.
        if (!isDev) {
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
        header("Content-Security-Policy", "default-src 'none'")
        header("Referrer-Policy", "no-referrer")
        header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
    }

    log.info(
        "Monitoring configured (call logging: {}, health filter: {})",
        "enabled",
        if (isDev) "disabled (all requests logged)" else "enabled (/health suppressed)",
    )
}
