package com.sinura.routes

import com.sinura.models.ErrorResponse
import com.sinura.models.SetUsernameRequest
import com.sinura.models.SetUsernameResponse
import com.sinura.models.UsernameCheckResponse
import com.sinura.plugins.JWT_AUTH
import com.sinura.plugins.Users
import com.sinura.plugins.authenticatedUserId
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.log
import io.ktor.server.auth.authenticate
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.patch
import io.ktor.server.routing.route
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.lowerCase
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import org.jetbrains.exposed.sql.update

/**
 * Username validation constants.
 */
private object UsernameValidation {
    const val MIN_LENGTH = 3
    const val MAX_LENGTH = 20

    /** Lowercase letters, digits, underscores, and dots. No leading/trailing/consecutive dots. */
    val VALID_PATTERN = Regex("^[a-z0-9_.]+$")
    val NO_LEADING_TRAILING_DOT = Regex("^[^.].*[^.]$|^[^.]\$")
    val NO_CONSECUTIVE_DOTS = Regex("^\\.\\.")

    fun validate(username: String): String? {
        val trimmed = username.trim().lowercase()
        return when {
            trimmed.length < MIN_LENGTH ->
                "Username must be at least $MIN_LENGTH characters long."
            trimmed.length > MAX_LENGTH ->
                "Username must be at most $MAX_LENGTH characters long."
            !VALID_PATTERN.matches(trimmed) ->
                "Username may only contain lowercase letters, digits, underscores, and dots."
            trimmed.startsWith('.') || trimmed.endsWith('.') ->
                "Username cannot start or end with a dot."
            trimmed.contains("..") ->
                "Username cannot contain consecutive dots."
            else -> null
        }
    }
}

/**
 * Registers username-related routes under /api/users.
 *
 * Routes:
 *   GET  /api/users/username/check?username={username}
 *        -- Checks whether a username is available (not taken by another user).
 *           Returns 200 with { username, available: true/false }.
 *
 *   PATCH /api/users/username
 *        -- Sets the username for the authenticated user.
 *           Request body: { "username": "john_doe" }
 *           Returns 200 with { username } on success.
 *           Returns 409 Conflict if the username is already taken.
 *           Returns 400 Bad Request if the username is invalid.
 */
fun Route.usernameRoutes(databaseReady: Boolean = true) {
    authenticate(JWT_AUTH) {
        route("/api/users") {

            /**
             * GET /api/users/username/check?username={username}
             *
             * Checks whether the given username is available.
             * The check is case-insensitive (all usernames are stored lowercase).
             *
             * Responses:
             *   200 OK                  -- UsernameCheckResponse JSON
             *   400 Bad Request         -- Missing or invalid username parameter
             *   401 Unauthorized        -- Invalid or missing JWT
             *   503 Service Unavailable -- Database not configured
             */
            get("/username/check") {
                val callerId = call.authenticatedUserId()
                if (callerId == null) {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(
                            error   = "unauthorized",
                            message = "Invalid authentication credentials",
                        ),
                    )
                    return@get
                }

                if (!databaseReady) {
                    call.respond(
                        HttpStatusCode.ServiceUnavailable,
                        ErrorResponse(
                            error   = "service_unavailable",
                            message = "Database connection is not configured",
                        ),
                    )
                    return@get
                }

                val rawUsername = call.request.queryParameters["username"]
                if (rawUsername.isNullOrBlank()) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = "Query parameter 'username' is required",
                        ),
                    )
                    return@get
                }

                val username = rawUsername.trim().lowercase()
                val validationError = UsernameValidation.validate(username)
                if (validationError != null) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = validationError,
                        ),
                    )
                    return@get
                }

                try {
                    val existingUser = newSuspendedTransaction {
                        Users.selectAll()
                            .where { Users.username.lowerCase() eq username }
                            .firstOrNull()
                    }

                    // Username is available if no row exists, OR if the only row
                    // with that username belongs to the caller themselves.
                    val available = existingUser == null ||
                        existingUser[Users.id] == callerId

                    call.respond(
                        HttpStatusCode.OK,
                        UsernameCheckResponse(username = username, available = available),
                    )
                } catch (e: Exception) {
                    call.application.log.error("Failed to check username availability for '$username'", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to check username availability",
                        ),
                    )
                }
            }

            /**
             * PATCH /api/users/username
             *
             * Sets the username for the authenticated user.
             * The username is stored in lowercase.
             *
             * Request body: { "username": "john_doe" }
             *
             * Responses:
             *   200 OK                  -- SetUsernameResponse JSON
             *   400 Bad Request         -- Invalid username (too short/long, bad chars)
             *   401 Unauthorized        -- Invalid or missing JWT
             *   409 Conflict            -- Username already taken by another user
             *   503 Service Unavailable -- Database not configured
             */
            patch("/username") {
                val callerId = call.authenticatedUserId()
                if (callerId == null) {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(
                            error   = "unauthorized",
                            message = "Invalid authentication credentials",
                        ),
                    )
                    return@patch
                }

                if (!databaseReady) {
                    call.respond(
                        HttpStatusCode.ServiceUnavailable,
                        ErrorResponse(
                            error   = "service_unavailable",
                            message = "Database connection is not configured",
                        ),
                    )
                    return@patch
                }

                val request = try {
                    call.receive<SetUsernameRequest>()
                } catch (e: Exception) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = "Invalid request body",
                        ),
                    )
                    return@patch
                }

                val username = request.username.trim().lowercase()
                val validationError = UsernameValidation.validate(username)
                if (validationError != null) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = validationError,
                        ),
                    )
                    return@patch
                }

                try {
                    val updated = newSuspendedTransaction {
                        // Check if the username is already taken by a different user.
                        val existingUser = Users.selectAll()
                            .where { Users.username.lowerCase() eq username }
                            .firstOrNull()

                        if (existingUser != null && existingUser[Users.id] != callerId) {
                            // Username is taken by someone else.
                            return@newSuspendedTransaction false
                        }

                        // Set the username for the caller.
                        Users.update({ Users.id eq callerId }) {
                            it[Users.username] = username
                        }
                        true
                    }

                    if (!updated) {
                        call.respond(
                            HttpStatusCode.Conflict,
                            ErrorResponse(
                                error   = "username_taken",
                                message = "This username is already taken. Please choose a different one.",
                            ),
                        )
                        return@patch
                    }

                    call.respond(
                        HttpStatusCode.OK,
                        SetUsernameResponse(username = username),
                    )
                } catch (e: Exception) {
                    call.application.log.error("Failed to set username for user $callerId", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to set username",
                        ),
                    )
                }
            }
        }
    }
}
