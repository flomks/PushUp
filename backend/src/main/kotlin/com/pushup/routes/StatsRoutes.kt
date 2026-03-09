package com.pushup.routes

import com.pushup.models.ErrorResponse
import com.pushup.plugins.JWT_AUTH
import com.pushup.plugins.authenticatedUserId
import com.pushup.service.StatsService
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.log
import io.ktor.server.auth.authenticate
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route
import java.time.LocalDate
import java.time.format.DateTimeParseException

/**
 * Registers all /api/stats/[daily|weekly|monthly|total|streak] routes.
 * Every endpoint requires a valid Supabase JWT (Bearer token).
 *
 * All database operations are wrapped in try-catch to prevent uncaught
 * exceptions from crashing the server process. Errors are logged and
 * a 500 response is returned to the client.
 */
fun Route.statsRoutes(statsService: StatsService) {
    authenticate(JWT_AUTH) {
        route("/api/stats") {

            get("/daily") {
                val userId = call.authenticatedUserId() ?: return@get call.respond(
                    HttpStatusCode.Unauthorized, ErrorResponse("unauthorized", "Missing or invalid user identity")
                )
                val date = call.parseDate("date") ?: return@get
                try {
                    call.respond(HttpStatusCode.OK, statsService.getDailyStats(userId, date))
                } catch (e: Exception) {
                    call.application.log.error("Failed to get daily stats for user $userId on $date", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse("internal_server_error", "Failed to retrieve daily statistics"),
                    )
                }
            }

            get("/weekly") {
                val userId = call.authenticatedUserId() ?: return@get call.respond(
                    HttpStatusCode.Unauthorized, ErrorResponse("unauthorized", "Missing or invalid user identity")
                )
                val weekStart = call.parseDate("week_start") ?: return@get
                try {
                    call.respond(HttpStatusCode.OK, statsService.getWeeklyStats(userId, weekStart))
                } catch (e: Exception) {
                    call.application.log.error("Failed to get weekly stats for user $userId starting $weekStart", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse("internal_server_error", "Failed to retrieve weekly statistics"),
                    )
                }
            }

            get("/monthly") {
                val userId = call.authenticatedUserId() ?: return@get call.respond(
                    HttpStatusCode.Unauthorized, ErrorResponse("unauthorized", "Missing or invalid user identity")
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
                    call.respond(HttpStatusCode.OK, statsService.getMonthlyStats(userId, month, year))
                } catch (e: Exception) {
                    call.application.log.error("Failed to get monthly stats for user $userId ($month/$year)", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse("internal_server_error", "Failed to retrieve monthly statistics"),
                    )
                }
            }

            get("/total") {
                val userId = call.authenticatedUserId() ?: return@get call.respond(
                    HttpStatusCode.Unauthorized, ErrorResponse("unauthorized", "Missing or invalid user identity")
                )
                try {
                    call.respond(HttpStatusCode.OK, statsService.getTotalStats(userId))
                } catch (e: Exception) {
                    call.application.log.error("Failed to get total stats for user $userId", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse("internal_server_error", "Failed to retrieve total statistics"),
                    )
                }
            }

            get("/streak") {
                val userId = call.authenticatedUserId() ?: return@get call.respond(
                    HttpStatusCode.Unauthorized, ErrorResponse("unauthorized", "Missing or invalid user identity")
                )
                try {
                    call.respond(HttpStatusCode.OK, statsService.getStreak(userId))
                } catch (e: Exception) {
                    call.application.log.error("Failed to get streak for user $userId", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse("internal_server_error", "Failed to retrieve streak data"),
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/**
 * Parses a required date query parameter (YYYY-MM-DD).
 * Responds with 400 and returns null on any error.
 */
private suspend fun ApplicationCall.parseDate(paramName: String): LocalDate? {
    val raw = request.queryParameters[paramName]
    if (raw.isNullOrBlank()) {
        respond(
            HttpStatusCode.BadRequest,
            ErrorResponse("bad_request", "Query parameter '$paramName' is required (format: YYYY-MM-DD)"),
        )
        return null
    }
    return try {
        LocalDate.parse(raw)
    } catch (e: DateTimeParseException) {
        respond(
            HttpStatusCode.BadRequest,
            ErrorResponse("bad_request", "Invalid date '$raw' for '$paramName'. Expected YYYY-MM-DD."),
        )
        null
    }
}
