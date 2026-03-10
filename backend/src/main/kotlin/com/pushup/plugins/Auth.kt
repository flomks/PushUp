package com.pushup.plugins

import com.auth0.jwk.JwkProviderBuilder
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
import java.net.URI
import java.util.UUID
import java.util.concurrent.TimeUnit

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
 * ## Supabase JWT signing modes
 *
 * Supabase changed its JWT signing strategy in 2024/2025:
 *
 * ### Legacy projects (HS256 / symmetric)
 * Tokens are signed with a shared secret (HMAC-SHA256).
 * The secret is available in the Supabase dashboard under
 * Settings > API > JWT Settings > JWT Secret.
 * Set `SUPABASE_JWT_SECRET` to use this mode.
 *
 * ### New projects (RS256 / asymmetric, JWKS)
 * Tokens are signed with an RSA private key. The corresponding public keys
 * are published at `<SUPABASE_URL>/auth/v1/.well-known/jwks.json`.
 * The JWT header contains a `kid` (key ID) field that identifies which key
 * to use for verification. Set `SUPABASE_URL` to use this mode.
 *
 * ## Mode selection (environment variables)
 *
 * | SUPABASE_URL | SUPABASE_JWT_SECRET | Mode used          |
 * |:------------:|:-------------------:|:------------------:|
 * | set          | set or unset        | JWKS (RS256)       |
 * | unset        | set                 | HS256 (legacy)     |
 * | unset        | unset               | disabled (401 all) |
 *
 * JWKS takes priority when both are set because new projects use RS256.
 *
 * ## Required environment variables
 *
 * JWKS mode:
 *   SUPABASE_URL    -- e.g. https://<ref>.supabase.co
 *   JWT_ISSUER      -- e.g. https://<ref>.supabase.co/auth/v1  (optional but recommended)
 *
 * HS256 mode (legacy):
 *   SUPABASE_JWT_SECRET  -- the raw JWT secret string from Supabase Settings
 *   JWT_ISSUER           -- e.g. https://<ref>.supabase.co/auth/v1  (optional but recommended)
 */
fun Application.configureAuth() {
    val supabaseUrl    = System.getenv("SUPABASE_URL")?.trimEnd('/')
    val jwtSecret      = System.getenv("SUPABASE_JWT_SECRET")
    val jwtIssuer      = System.getenv("JWT_ISSUER")
    val isDev          = System.getenv("KTOR_ENV") != "production"

    // -------------------------------------------------------------------------
    // Determine which mode to use
    // -------------------------------------------------------------------------

    val useJwks = !supabaseUrl.isNullOrBlank()
    val useHs256 = !useJwks && !jwtSecret.isNullOrBlank()

    if (!useJwks && !useHs256) {
        if (!isDev) {
            throw IllegalStateException(
                "JWT auth is not configured. Set SUPABASE_URL (for new projects using RS256/JWKS) " +
                    "or SUPABASE_JWT_SECRET (for legacy projects using HS256)."
            )
        }
        log.warn(
            "JWT auth not configured -- all JWT-protected routes will return 401. " +
                "Set SUPABASE_URL (RS256/JWKS) or SUPABASE_JWT_SECRET (HS256/legacy)."
        )
        install(Authentication) {
            jwt(JWT_AUTH) {
                verifier(JWT.require(Algorithm.HMAC256("dev-placeholder-not-a-real-secret")).build())
                validate { null }
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

    if (jwtIssuer.isNullOrBlank() && !isDev) {
        throw IllegalStateException(
            "JWT_ISSUER must be set in production " +
                "(e.g., https://<project-ref>.supabase.co/auth/v1)"
        )
    }

    if (useJwks) {
        configureJwksAuth(supabaseUrl!!, jwtIssuer, isDev)
    } else {
        configureHs256Auth(jwtSecret!!, jwtIssuer, isDev)
    }
}

// ---------------------------------------------------------------------------
// JWKS mode (RS256 -- new Supabase projects)
// ---------------------------------------------------------------------------

/**
 * Installs JWT authentication using Supabase's JWKS endpoint.
 *
 * Public keys are fetched from `<supabaseUrl>/auth/v1/.well-known/jwks.json`
 * and cached locally. The `kid` claim in the JWT header selects the correct key.
 *
 * Key cache settings:
 * - Cached for 10 minutes (Supabase rotates keys infrequently)
 * - Up to 5 keys cached simultaneously (Supabase typically has 1-2 active keys)
 * - Rate-limited to 10 JWKS fetches per minute to prevent hammering the endpoint
 */
private fun Application.configureJwksAuth(
    supabaseUrl: String,
    jwtIssuer: String?,
    isDev: Boolean,
) {
    val jwksUrl = "$supabaseUrl/auth/v1/.well-known/jwks.json"
    log.info(
        "JWT auth: mode=JWKS (RS256) " +
            "jwks_url='$jwksUrl' " +
            "issuer='${jwtIssuer ?: "(not checked)"}' " +
            "audience='authenticated'"
    )

    val jwkProvider = JwkProviderBuilder(URI(jwksUrl).toURL())
        .cached(5, 10, TimeUnit.MINUTES)
        .rateLimited(10, 1, TimeUnit.MINUTES)
        .build()

    install(Authentication) {
        jwt(JWT_AUTH) {
            realm = "pushup-backend"

            verifier(jwkProvider) {
                if (!jwtIssuer.isNullOrBlank()) withIssuer(jwtIssuer)
                withAudience("authenticated")
                acceptLeeway(10) // 10-second clock skew tolerance
            }

            validate { credential ->
                val sub = credential.payload.subject
                if (sub != null) JWTPrincipal(credential.payload) else null
            }

            challenge { _, _ ->
                val authHeader = call.request.headers["Authorization"]
                val rawToken = authHeader?.removePrefix("Bearer ")?.trim()
                if (rawToken != null) {
                    try {
                        val unverified = JWT.decode(rawToken)
                        call.application.log.warn(
                            "JWT rejected (JWKS mode). " +
                                "kid='${unverified.keyId}' " +
                                "iss='${unverified.issuer}' " +
                                "aud=${unverified.audience} " +
                                "sub='${unverified.subject}' " +
                                "exp=${unverified.expiresAt} " +
                                "configured_issuer='$jwtIssuer' " +
                                "jwks_url='$jwksUrl'"
                        )
                    } catch (_: Exception) {
                        call.application.log.warn("JWT rejected (JWKS mode) -- token could not be decoded.")
                    }
                } else {
                    call.application.log.warn("JWT rejected (JWKS mode) -- no Authorization header present.")
                }

                call.respond(
                    HttpStatusCode.Unauthorized,
                    ErrorResponse(error = "unauthorized", message = "Token is invalid or expired"),
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// HS256 mode (legacy Supabase projects)
// ---------------------------------------------------------------------------

/**
 * Installs JWT authentication using a shared HMAC-SHA256 secret.
 *
 * Used for Supabase projects created before the 2024/2025 key redesign.
 * These projects sign JWTs with a symmetric secret available in the dashboard
 * under Settings > API > JWT Settings > JWT Secret.
 */
private fun Application.configureHs256Auth(
    jwtSecret: String,
    jwtIssuer: String?,
    isDev: Boolean,
) {
    log.info(
        "JWT auth: mode=HS256 (legacy) " +
            "issuer='${jwtIssuer ?: "(not checked)"}' " +
            "audience='authenticated'"
    )

    val algorithm = Algorithm.HMAC256(jwtSecret)

    // Signature-only decoder for diagnostic logging on rejection.
    val diagnosticDecoder = JWT.require(algorithm).build()

    install(Authentication) {
        jwt(JWT_AUTH) {
            realm = "pushup-backend"

            val verifierBuilder = JWT.require(algorithm)
            if (!jwtIssuer.isNullOrBlank()) verifierBuilder.withIssuer(jwtIssuer)
            verifierBuilder.withAudience("authenticated")
            verifier(verifierBuilder.build())

            validate { credential ->
                val sub = credential.payload.subject
                if (sub != null) JWTPrincipal(credential.payload) else null
            }

            challenge { _, _ ->
                val authHeader = call.request.headers["Authorization"]
                val rawToken = authHeader?.removePrefix("Bearer ")?.trim()
                if (rawToken != null) {
                    try {
                        val decoded = diagnosticDecoder.verify(rawToken)
                        call.application.log.warn(
                            "JWT rejected (HS256 mode) -- signature OK but claim mismatch. " +
                                "iss='${decoded.issuer}' " +
                                "aud=${decoded.audience} " +
                                "sub='${decoded.subject}' " +
                                "exp=${decoded.expiresAt} " +
                                "configured_issuer='$jwtIssuer'"
                        )
                    } catch (e: JWTVerificationException) {
                        try {
                            val unverified = JWT.decode(rawToken)
                            call.application.log.warn(
                                "JWT rejected (HS256 mode) -- ${e.javaClass.simpleName}: ${e.message}. " +
                                    "iss='${unverified.issuer}' " +
                                    "aud=${unverified.audience} " +
                                    "sub='${unverified.subject}' " +
                                    "exp=${unverified.expiresAt} " +
                                    "configured_issuer='$jwtIssuer'"
                            )
                        } catch (_: Exception) {
                            call.application.log.warn(
                                "JWT rejected (HS256 mode) -- ${e.javaClass.simpleName}: ${e.message}. " +
                                    "Token could not be decoded for diagnostics."
                            )
                        }
                    }
                } else {
                    call.application.log.warn("JWT rejected (HS256 mode) -- no Authorization header present.")
                }

                call.respond(
                    HttpStatusCode.Unauthorized,
                    ErrorResponse(error = "unauthorized", message = "Token is invalid or expired"),
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
