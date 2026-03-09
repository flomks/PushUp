package com.pushup.routes

import com.pushup.models.ErrorResponse
import com.pushup.plugins.JWT_AUTH
import com.pushup.plugins.authenticatedUserId
import com.pushup.service.UserDataService
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.log
import io.ktor.server.auth.authenticate
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route

/**
 * Registers the GET /api/user/data route.
 *
 * This endpoint returns a combined overview of the authenticated user's data:
 * - User profile (id, email, display name, avatar)
 * - All-time workout statistics (total push-ups, sessions, earned credits, quality, streak)
 * - Time-credit balance (earned, spent, available)
 * - Streak information (current streak, longest streak, last workout date)
 *
 * The client can call this single endpoint after login to populate a dashboard
 * screen without making multiple separate requests.
 *
 * Responses:
 *   200 OK                  -- [UserDataResponse] JSON
 *   401 Unauthorized        -- Invalid JWT or malformed user ID
 *   404 Not Found           -- User profile not found in the database
 *   503 Service Unavailable -- Database not configured
 */
fun Route.userDataRoutes(
    userDataService: UserDataService,
    databaseReady: Boolean = true,
) {
    authenticate(JWT_AUTH) {
        route("/api/user") {
            get("/data") {
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
                    val data = userDataService.getUserData(userId)
                    if (data == null) {
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
                    call.respond(HttpStatusCode.OK, data)
                } catch (e: Exception) {
                    call.application.log.error("Failed to get user data for $userId", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to retrieve user data",
                        ),
                    )
                }
            }
        }
    }
}
