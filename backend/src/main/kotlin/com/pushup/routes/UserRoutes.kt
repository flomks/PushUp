package com.pushup.routes

import com.pushup.models.ErrorResponse
import com.pushup.models.UserResponse
import com.pushup.plugins.JWT_AUTH
import com.pushup.plugins.Users
import com.pushup.plugins.authenticatedUserId
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.log
import io.ktor.server.auth.authenticate
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import java.time.format.DateTimeFormatter

/**
 * Registers all user-related API routes under /api.
 *
 * @param databaseReady Whether the database connection was successfully
 *                      initialised. When false, all DB-dependent endpoints
 *                      return 503 instead of an opaque 500.
 *
 * Routes:
 *   GET /api/me  -- Returns the currently authenticated user's profile.
 *                   Requires a valid Supabase JWT in the Authorization header.
 */
fun Route.userRoutes(databaseReady: Boolean = true) {
    route("/api") {
        authenticate(JWT_AUTH) {
            /**
             * GET /api/me
             *
             * Extracts the user ID from the validated JWT, queries the
             * public.users table via Exposed, and returns the user profile.
             *
             * Responses:
             *   200 OK                  -- UserResponse JSON
             *   401 Unauthorized        -- Invalid JWT or malformed user ID
             *   404 Not Found           -- User record not found in the database
             *   503 Service Unavailable -- Database not configured
             */
            get("/me") {
                val userId = call.authenticatedUserId()
                if (userId == null) {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(
                            error   = "unauthorized",
                            message = "Invalid authentication credentials",
                        ),
                    )
                    return@get
                }

                // Guard: if the database was not initialised (dev mode without
                // DATABASE_URL), return 503 instead of an opaque 500.
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

                try {
                    // newSuspendedTransaction suspends the coroutine instead of
                    // blocking a thread, keeping Ktor's event loop healthy.
                    val userRow = newSuspendedTransaction {
                        Users.selectAll()
                            .where { Users.id eq userId }
                            .singleOrNull()
                    }

                    if (userRow == null) {
                        call.respond(
                            HttpStatusCode.NotFound,
                            ErrorResponse(
                                error   = "user_not_found",
                                message = "No user profile found for the authenticated user. " +
                                          "Ensure the Supabase auth trigger has run.",
                            ),
                        )
                        return@get
                    }

                    call.respond(
                        HttpStatusCode.OK,
                        UserResponse(
                            id          = userRow[Users.id].toString(),
                            email       = userRow[Users.email],
                            username    = userRow[Users.username],
                            displayName = userRow[Users.displayName],
                            avatarUrl   = userRow[Users.avatarUrl],
                            createdAt   = userRow[Users.createdAt].format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
                            updatedAt   = userRow[Users.updatedAt].format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
                        ),
                    )
                } catch (e: Exception) {
                    call.application.log.error("Failed to get user profile for $userId", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to retrieve user profile",
                        ),
                    )
                }
            }
        }
    }
}
