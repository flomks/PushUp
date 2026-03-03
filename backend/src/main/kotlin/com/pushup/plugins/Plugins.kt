package com.pushup.plugins

import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.jwt.JWTPrincipal
import io.ktor.server.auth.jwt.jwt
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.plugins.cors.routing.CORS
import io.ktor.server.plugins.defaultheaders.DefaultHeaders
import io.ktor.server.request.path
import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import org.slf4j.event.Level

fun Application.configureCORS() {
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

        val allowedHosts = System.getenv("CORS_ALLOWED_HOSTS")
        if (allowedHosts != null) {
            allowedHosts.split(",").map { it.trim() }.forEach { host ->
                allowHost(host, schemes = listOf("https"))
            }
        } else {
            anyHost()
        }
    }
}

fun Application.configureAuth() {
    val jwtSecret = System.getenv("SUPABASE_JWT_SECRET") ?: ""
    val jwtIssuer = System.getenv("JWT_ISSUER") ?: "https://api.pushup.app"
    val jwtRealm = "pushup-backend"

    if (jwtSecret.isNotBlank()) {
        install(Authentication) {
            jwt("supabase") {
                realm = jwtRealm
                verifier(
                    JWT.require(Algorithm.HMAC256(jwtSecret))
                        .withIssuer(jwtIssuer)
                        .build()
                )
                validate { credential ->
                    val sub = credential.payload.subject
                    if (sub != null) {
                        JWTPrincipal(credential.payload)
                    } else {
                        null
                    }
                }
            }
        }
    }
}

fun Application.configureMonitoring() {
    install(CallLogging) {
        level = Level.INFO
        filter { call -> call.request.path().startsWith("/") }
    }
    install(DefaultHeaders) {
        header("X-Engine", "Ktor")
    }
}
