package com.pushup.routes

import com.pushup.models.UserResponse
import com.pushup.plugins.ErrorResponse
import com.pushup.plugins.JWT_AUTH
import com.pushup.plugins.Users
import com.pushup.plugins.authenticatedUserId
import io.ktor.http.HttpStatusCode
import io.ktor.server.auth.authenticate
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction

/**
 * Registers all user-related API routes under /api.
 *
 * Routes:
 *   GET /api/me  -- Returns the currently authenticated user's profile.
 *                   Requires a valid Supabase JWT in the Authorization header.
 */
fun Route.userRoutes() {
    route("/api") {
        authenticate(JWT_AUTH) {
            /**
             * GET /api/me
             *
             * Extracts the user ID from the validated JWT, queries the
             * public.users table via Exposed, and returns the user profile.
             *
             * Responses:
             *   200 OK        -- UserResponse JSON
             *   404 Not Found -- User record not found in the database
             */
            get("/me") {
                val userId = call.authenticatedUserId()

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
                        displayName = userRow[Users.displayName],
                        avatarUrl   = userRow[Users.avatarUrl],
                        createdAt   = userRow[Users.createdAt].toString(),
                        updatedAt   = userRow[Users.updatedAt].toString(),
                    ),
                )
            }
        }
    }
}
