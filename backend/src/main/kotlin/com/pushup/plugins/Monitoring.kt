package com.pushup.plugins

import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.plugins.defaultheaders.DefaultHeaders
import io.ktor.server.request.path
import org.slf4j.event.Level

fun Application.configureMonitoring() {
    install(CallLogging) {
        level = Level.INFO
        // Health-Check-Requests nicht loggen -- wuerden die Logs fluten
        filter { call -> !call.request.path().startsWith("/health") }
    }
    install(DefaultHeaders) {
        // Verhindert MIME-Type-Sniffing
        header("X-Content-Type-Options", "nosniff")
        // Verhindert Einbettung in iframes (Clickjacking-Schutz)
        header("X-Frame-Options", "DENY")
        // HSTS: Browser merkt sich fuer 1 Jahr dass nur HTTPS erlaubt ist
        header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        // CSP: Nur eigene Ressourcen erlaubt -- API gibt nur JSON aus, kein HTML
        header("Content-Security-Policy", "default-src 'none'")
        // Kein Referrer-Header bei Cross-Origin-Requests
        header("Referrer-Policy", "no-referrer")
        // Deaktiviert Browser-Features die eine API nicht benoetigt
        header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
    }
}
