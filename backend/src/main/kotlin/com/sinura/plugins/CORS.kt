package com.sinura.plugins

import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.cors.routing.CORS

fun Application.configureCORS() {
    val allowedHosts = System.getenv("CORS_ALLOWED_HOSTS")
    val isDev = System.getenv("KTOR_ENV") != "production"

    install(CORS) {
        allowMethod(HttpMethod.Options)
        allowMethod(HttpMethod.Get)
        allowMethod(HttpMethod.Post)
        allowMethod(HttpMethod.Put)
        allowMethod(HttpMethod.Patch)
        allowMethod(HttpMethod.Delete)
        allowHeader(HttpHeaders.Authorization)
        allowHeader(HttpHeaders.ContentType)
        allowHeader(HttpHeaders.Accept)

        when {
            !allowedHosts.isNullOrBlank() -> {
                // Explicit host list: production uses https only, dev also allows http
                // so that localhost origins (e.g. http://localhost:3000) work.
                val schemes = if (isDev) listOf("http", "https") else listOf("https")
                allowedHosts
                    .split(",")
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                    .forEach { host -> allowHost(host, schemes = schemes) }
            }
            isDev -> anyHost()
            else -> throw IllegalStateException(
                "CORS_ALLOWED_HOSTS must be set in production " +
                    "(comma-separated list, e.g., 'app.pushup.com,api.pushup.com')"
            )
        }
    }
}
