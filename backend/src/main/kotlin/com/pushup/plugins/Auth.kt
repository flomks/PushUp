package com.pushup.plugins

import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import com.pushup.models.ErrorResponse
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.install
import io.ktor.server.application.log
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.jwt.JWTPrincipal
import io.ktor.server.auth.jwt.jwt
import io.ktor.server.auth.principal
import io.ktor.server.response.respond
import java.util.UUID

// ---------------------------------------------------------------------------
// JWT auth provider name
// ---------------------------------------------------------------------------

/** Name of the JWT authentication provider registered with Ktor. */
const val JWT_AUTH = "supabase"

// ---------------------------------------------------------------------------
// Plugin installer
// ---------------------------------------------------------------------------

/**
 * Configures Ktor's JWT authentication plugin to validate Supabase Access Tokens.
 *
 * Supabase signs its JWTs with HS256 using the project's JWT secret.
 * The secret is available in the Supabase dashboard under
 * Settings > API > JWT Settings > JWT Secret.
 *
 * Required environment variables:
 *   SUPABASE_JWT_SECRET  -- the raw JWT secret string from Supabase Settings
 *   JWT_ISSUER           -- e.g. https://<ref>.supabase.co/auth/v1
 *
 * In non-production mode (KTOR_ENV != "production") the server will log a
 * warning and skip JWT configuration if SUPABASE_JWT_SECRET is not set.
 */
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
        jwt(JWT_AUTH) {
            realm = jwtRealm

            val verifierBuilder = JWT.require(Algorithm.HMAC256(jwtSecret))
            if (!jwtIssuer.isNullOrBlank()) {
                verifierBuilder.withIssuer(jwtIssuer)
            }
            // Supabase sets aud = "authenticated" for logged-in user tokens.
            // This rejects service_role and anon tokens.
            verifierBuilder.withAudience("authenticated")
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
                    ErrorResponse(
                        error   = "unauthorized",
                        message = "Token is invalid or expired",
                    ),
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Extension helpers for route handlers
// ---------------------------------------------------------------------------

/**
 * Extracts the authenticated Supabase user ID (UUID) from the JWT principal.
 *
 * Returns null if the principal is absent or the subject claim is not a valid
 * UUID -- callers should respond with 401 in that case.
 */
fun ApplicationCall.authenticatedUserId(): UUID? {
    val principal = principal<JWTPrincipal>() ?: return null
    val subject = principal.payload.subject ?: return null
    return try {
        UUID.fromString(subject)
    } catch (_: IllegalArgumentException) {
        null
    }
}
