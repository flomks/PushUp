package com.pushup.plugins

import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.application.log
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.jwt.JWTPrincipal
import io.ktor.server.auth.jwt.jwt
import io.ktor.server.response.respond
import kotlinx.serialization.Serializable

@Serializable
data class ErrorResponse(val error: String)

fun Application.configureAuth() {
    val jwtSecret = System.getenv("SUPABASE_JWT_SECRET")
    val isDev = System.getenv("KTOR_ENV") != "production"

    if (jwtSecret.isNullOrBlank()) {
        if (!isDev) {
            throw IllegalStateException(
                "SUPABASE_JWT_SECRET must be set in production. " +
                    "Set KTOR_ENV to a value other than 'production' to disable this check."
            )
        }
        log.warn("SUPABASE_JWT_SECRET not set -- JWT auth is DISABLED (non-production mode)")
        return
    }

    val jwtIssuer = System.getenv("JWT_ISSUER")
    if (jwtIssuer.isNullOrBlank() && !isDev) {
        throw IllegalStateException(
            "JWT_ISSUER must be set in production " +
                "(e.g., https://<project-ref>.supabase.co/auth/v1)"
        )
    }

    val jwtRealm = "pushup-backend"

    install(Authentication) {
        jwt("supabase") {
            realm = jwtRealm

            val verifierBuilder = JWT.require(Algorithm.HMAC256(jwtSecret))
            if (!jwtIssuer.isNullOrBlank()) {
                verifierBuilder.withIssuer(jwtIssuer)
            }
            verifier(verifierBuilder.build())

            validate { credential ->
                val sub = credential.payload.subject
                if (sub != null) {
                    JWTPrincipal(credential.payload)
                } else {
                    null
                }
            }

            challenge { _, _ ->
                call.respond(
                    HttpStatusCode.Unauthorized,
                    ErrorResponse(error = "Token is invalid or expired"),
                )
            }
        }
    }
}
