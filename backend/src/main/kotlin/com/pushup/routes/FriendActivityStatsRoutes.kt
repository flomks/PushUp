package com.pushup.routes

import com.pushup.dto.StatsPeriod
import com.pushup.models.ErrorResponse
import com.pushup.plugins.JWT_AUTH
import com.pushup.plugins.authenticatedUserId
import com.pushup.service.FriendActivityStatsResult
import com.pushup.service.FriendActivityStatsService
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.log
import io.ktor.server.auth.authenticate
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route
import java.util.UUID

/**
 * Registers the GET /api/friends/{id}/stats route.
 *
 * Returns aggregated push-up activity statistics for a specific friend.
 * Access is restricted to users who share an active (accepted) friendship
 * with the target user -- non-friends receive 403 Forbidden.
 *
 * Route:
 *   GET /api/friends/{id}/stats?period=day|week|month
 *
 * Path parameters:
 *   id -- UUID of the friend whose stats are requested.
 *
 * Query parameters:
 *   period (required) -- one of: "day", "week", "month"
 *
 * Response body (200 OK):
 * ```json
 * {
 *   "friendId": "<uuid>",
 *   "period": "week",
 *   "dateRange": { "from": "2026-03-02", "to": "2026-03-08" },
 *   "pushupCount": 42,
 *   "totalSessions": 5,
 *   "totalEarnedSeconds": 252,
 *   "averageQuality": 0.87
 * }
 * ```
 *
 * Error responses:
 *   400 Bad Request         -- Missing or invalid `period` or `id` parameter
 *   401 Unauthorized        -- Invalid or missing JWT
 *   403 Forbidden           -- Caller and target user are not active friends
 *   503 Service Unavailable -- Database not configured
 *
 * @param friendActivityStatsService Service that handles the business logic.
 * @param databaseReady              Whether the database connection was successfully
 *                                   initialised. When false, returns 503.
 */
fun Route.friendActivityStatsRoutes(
    friendActivityStatsService: FriendActivityStatsService = FriendActivityStatsService(),
    databaseReady: Boolean = true,
) {
    authenticate(JWT_AUTH) {
        route("/api/friends") {

            /**
             * GET /api/friends/{id}/stats?period=day|week|month
             */
            get("/{id}/stats") {

                // ----------------------------------------------------------
                // Auth guard
                // ----------------------------------------------------------
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

                // ----------------------------------------------------------
                // Database availability guard
                // ----------------------------------------------------------
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

                // ----------------------------------------------------------
                // Parse and validate the {id} path parameter
                // ----------------------------------------------------------
                val friendId = try {
                    UUID.fromString(call.parameters["id"])
                } catch (e: IllegalArgumentException) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = "Path parameter 'id' must be a valid UUID",
                        ),
                    )
                    return@get
                }

                // ----------------------------------------------------------
                // Parse and validate the ?period= query parameter
                // ----------------------------------------------------------
                val periodParam = call.request.queryParameters["period"]
                val period = StatsPeriod.fromQueryParam(periodParam)
                if (period == null) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = "Query parameter 'period' is required and must be one of: day, week, month",
                        ),
                    )
                    return@get
                }

                // ----------------------------------------------------------
                // Delegate to service
                // ----------------------------------------------------------
                try {
                    when (val result = friendActivityStatsService.getStats(callerId, friendId, period)) {
                        is FriendActivityStatsResult.Success -> {
                            call.respond(HttpStatusCode.OK, result.stats)
                        }

                        is FriendActivityStatsResult.NotFriends -> {
                            call.respond(
                                HttpStatusCode.Forbidden,
                                ErrorResponse(
                                    error   = "forbidden",
                                    message = "You are not friends with this user",
                                ),
                            )
                        }

                        is FriendActivityStatsResult.FriendNotFound -> {
                            call.respond(
                                HttpStatusCode.NotFound,
                                ErrorResponse(
                                    error   = "not_found",
                                    message = "User not found",
                                ),
                            )
                        }
                    }
                } catch (e: Exception) {
                    call.application.log.error(
                        "Failed to retrieve activity stats for friend=$friendId caller=$callerId period=$period", e
                    )
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to retrieve friend activity statistics",
                        ),
                    )
                }
            }
        }
    }
}
