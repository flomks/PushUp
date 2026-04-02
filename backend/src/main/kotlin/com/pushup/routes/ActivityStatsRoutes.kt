package com.pushup.routes

import com.pushup.models.ErrorResponse
import com.pushup.plugins.JWT_AUTH
import com.pushup.plugins.authenticatedUserId
import com.pushup.service.ActivityStatsService
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.log
import io.ktor.server.auth.authenticate
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route

/**
 * Registers unified activity stats endpoints under `/api/stats/activity/`.
 *
 * These endpoints aggregate data from ALL workout types (push-ups + jogging),
 * unlike the existing `/api/stats/` endpoints which are push-up-only.
 */
fun Route.activityStatsRoutes(activityStatsService: ActivityStatsService) {
    authenticate(JWT_AUTH) {
        route("/api/stats/activity") {

            /**
             * GET /api/stats/activity/heatmap?month=M&year=Y
             *
             * Returns per-day activity data for the requested month, suitable
             * for rendering a GitHub-style contribution heatmap.
             */
            get("/heatmap") {
                val userId = call.authenticatedUserId() ?: return@get call.respond(
                    HttpStatusCode.Unauthorized,
                    ErrorResponse("unauthorized", "Missing or invalid user identity"),
                )
                val monthParam = call.request.queryParameters["month"]
                val yearParam = call.request.queryParameters["year"]

                if (monthParam.isNullOrBlank() || yearParam.isNullOrBlank()) {
                    return@get call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse("bad_request", "Query parameters 'month' (1-12) and 'year' are required"),
                    )
                }
                val month = monthParam.toIntOrNull()
                val year = yearParam.toIntOrNull()
                if (month == null || month !in 1..12) {
                    return@get call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse("bad_request", "Invalid 'month' value '$monthParam'. Must be 1-12."),
                    )
                }
                if (year == null || year < 2000 || year > 2100) {
                    return@get call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse("bad_request", "Invalid 'year' value '$yearParam'. Must be between 2000 and 2100."),
                    )
                }

                try {
                    call.respond(HttpStatusCode.OK, activityStatsService.getMonthlyHeatmap(userId, month, year))
                } catch (e: Exception) {
                    call.application.log.error("Failed to get activity heatmap for user $userId ($month/$year)", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse("internal_server_error", "Failed to retrieve activity heatmap"),
                    )
                }
            }

            /**
             * GET /api/stats/activity/streak
             *
             * Returns the unified activity streak across all workout types.
             */
            get("/streak") {
                val userId = call.authenticatedUserId() ?: return@get call.respond(
                    HttpStatusCode.Unauthorized,
                    ErrorResponse("unauthorized", "Missing or invalid user identity"),
                )

                try {
                    call.respond(HttpStatusCode.OK, activityStatsService.getActivityStreak(userId))
                } catch (e: Exception) {
                    call.application.log.error("Failed to get activity streak for user $userId", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse("internal_server_error", "Failed to retrieve activity streak"),
                    )
                }
            }
        }
    }
}
