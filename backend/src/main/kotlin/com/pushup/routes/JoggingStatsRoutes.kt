package com.pushup.routes

import com.pushup.models.ErrorResponse
import com.pushup.plugins.JWT_AUTH
import com.pushup.service.JoggingStatsService
import io.ktor.http.HttpStatusCode
import io.ktor.server.auth.authenticate
import io.ktor.server.auth.jwt.JWTPrincipal
import io.ktor.server.auth.principal
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route
import java.util.UUID

/**
 * Registers jogging stats API routes under `/api/jogging/`.
 *
 * All routes require JWT authentication.
 *
 * Routes:
 * - GET /api/jogging/stats/total   -- Total jogging stats for the authenticated user
 * - GET /api/jogging/sessions      -- Session history for the authenticated user
 * - GET /api/jogging/sessions/{id}/route -- Route points for a specific session
 */
fun Route.joggingStatsRoutes(service: JoggingStatsService) {
    authenticate(JWT_AUTH) {
        route("/api/jogging") {

            // GET /api/jogging/stats/total
            get("/stats/total") {
                val userId = call.principal<JWTPrincipal>()
                    ?.payload?.subject
                    ?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    ?: return@get call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse("Invalid or missing JWT subject"),
                    )

                val stats = service.getTotalStats(userId)
                call.respond(HttpStatusCode.OK, stats)
            }

            // GET /api/jogging/sessions
            get("/sessions") {
                val userId = call.principal<JWTPrincipal>()
                    ?.payload?.subject
                    ?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    ?: return@get call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse("Invalid or missing JWT subject"),
                    )

                val sessions = service.getSessionHistory(userId)
                call.respond(HttpStatusCode.OK, sessions)
            }

            // GET /api/jogging/sessions/{id}/route
            get("/sessions/{id}/route") {
                val userId = call.principal<JWTPrincipal>()
                    ?.payload?.subject
                    ?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    ?: return@get call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse("Invalid or missing JWT subject"),
                    )

                val sessionId = call.parameters["id"]
                    ?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    ?: return@get call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse("Invalid session ID"),
                    )

                val routePoints = service.getRoutePoints(sessionId, userId)
                call.respond(HttpStatusCode.OK, routePoints)
            }
        }
    }
}
