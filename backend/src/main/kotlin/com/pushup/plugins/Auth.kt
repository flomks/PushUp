package com.pushup.plugins

import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import com.auth0.jwt.exceptions.JWTVerificationException
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
 * In non-production mode (KTOR_ENV != "production") the server will still
 * install the Authentication plugin. If SUPABASE_JWT_SECRET is not set, a
 * no-op provider is registered so that routes using authenticate(JWT_AUTH)
 * always return 401 -- the server starts and routes are reachable, but all
 * protected endpoints reject requests until credentials are configured.
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
        // Dev mode without a secret: install a provider that always rejects.
        // This keeps the server startable while making the missing config obvious.
        log.warn(
            "SUPABASE_JWT_SECRET not set -- all JWT-protected routes will return 401. " +
                "Set SUPABASE_JWT_SECRET to enable authentication."
        )
        install(Authentication) {
            jwt(JWT_AUTH) {
                verifier(JWT.require(Algorithm.HMAC256("dev-placeholder-not-a-real-secret")).build())
                validate { null } // always reject
                challenge { _, _ ->
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(
                            error   = "unauthorized",
                            message = "JWT authentication is not configured on this server",
                        ),
                    )
                }
            }
        }
        return
    }

    val jwtIssuer = System.getenv("JWT_ISSUER")
    if (jwtIssuer.isNullOrBlank() && !isDev) {
        throw IllegalStateException(
            "JWT_ISSUER must be set in production " +
                "(e.g., https://<project-ref>.supabase.co/auth/v1)"
        )
    }

    // Log the configured issuer at startup so mismatches are immediately visible.
    log.info("JWT auth: issuer='${jwtIssuer ?: "(not set -- issuer check disabled)"}' audience='authenticated'")

    install(Authentication) {
        jwt(JWT_AUTH) {
            realm = "pushup-backend"

            val algorithm = Algorithm.HMAC256(jwtSecret)

            // Build a verifier WITHOUT audience/issuer first so we can decode
            // the token for diagnostic logging when verification fails.
            val diagnosticDecoder = JWT.require(algorithm).build()

            val verifierBuilder = JWT.require(algorithm)
            if (!jwtIssuer.isNullOrBlank()) {
                verifierBuilder.withIssuer(jwtIssuer)
            }
            // Supabase sets aud = "authenticated" for logged-in user tokens.
            // This rejects service_role and anon tokens.
            verifierBuilder.withAudience("authenticated")
            verifier(verifierBuilder.build())

            validate { credential ->
                val sub = credential.payload.subject
                if (sub != null) JWTPrincipal(credential.payload) else null
            }

            challenge { defaultScheme, realm ->
                // Attempt to decode the raw token (without full verification) so we
                // can log exactly which claim caused the rejection. This is safe
                // because we only log non-sensitive claims (iss, aud, sub, exp).
                val authHeader = call.request.headers["Authorization"]
                val rawToken = authHeader?.removePrefix("Bearer ")?.trim()
                if (rawToken != null) {
                    try {
                        val decoded = diagnosticDecoder.verify(rawToken)
                        // If we get here the signature is valid but issuer/audience failed.
                        call.application.log.warn(
                            "JWT rejected -- signature OK but claim mismatch. " +
                                "iss='${decoded.issuer}' " +
                                "aud=${decoded.audience} " +
                                "sub='${decoded.subject}' " +
                                "exp=${decoded.expiresAt} " +
                                "configured_issuer='$jwtIssuer'"
                        )
                    } catch (e: JWTVerificationException) {
                        // Signature or expiry failed -- log the reason without the token value.
                        try {
                            val unverified = JWT.decode(rawToken)
                            call.application.log.warn(
                                "JWT rejected -- ${e.javaClass.simpleName}: ${e.message}. " +
                                    "iss='${unverified.issuer}' " +
                                    "aud=${unverified.audience} " +
                                    "sub='${unverified.subject}' " +
                                    "exp=${unverified.expiresAt} " +
                                    "configured_issuer='$jwtIssuer'"
                            )
                        } catch (_: Exception) {
                            call.application.log.warn(
                                "JWT rejected -- ${e.javaClass.simpleName}: ${e.message}. " +
                                    "Token could not be decoded for diagnostics."
                            )
                        }
                    }
                } else {
                    call.application.log.warn("JWT rejected -- no Authorization header present")
                }

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
