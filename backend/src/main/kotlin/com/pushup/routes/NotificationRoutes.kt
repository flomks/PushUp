package com.pushup.routes

import com.pushup.models.ErrorResponse
import com.pushup.plugins.JWT_AUTH
import com.pushup.plugins.authenticatedUserId
import com.pushup.service.MarkNotificationReadResult
import com.pushup.service.NotificationService
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.log
import io.ktor.server.auth.authenticate
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.RoutingCall
import io.ktor.server.routing.get
import io.ktor.server.routing.patch
import io.ktor.server.routing.route
import java.util.UUID

/**
 * Registers all /api/notifications routes.
 *
 * Routes:
 *   GET   /api/notifications             -- Returns all notifications for the caller.
 *   PATCH /api/notifications/read-all    -- Marks all notifications as read.
 *   PATCH /api/notifications/{id}/read   -- Marks a single notification as read.
 *
 * @param notificationService Service that handles notification business logic.
 * @param databaseReady       When false, all DB-dependent endpoints return 503.
 */
fun Route.notificationRoutes(
    notificationService: NotificationService = NotificationService(),
    databaseReady: Boolean = true,
) {
    authenticate(JWT_AUTH) {
        route("/api/notifications") {

            /**
             * GET /api/notifications
             *
             * Returns all in-app notifications for the authenticated user,
             * ordered by creation time descending (newest first).
             *
             * Responses:
             *   200 OK                  -- [NotificationsListResponse] JSON
             *   401 Unauthorized        -- Invalid or missing JWT
             *   503 Service Unavailable -- Database not configured
             */
            get {
                val callerId = call.requireAuthOrRespond() ?: return@get
                if (!call.requireDatabaseOrRespond(databaseReady)) return@get

                try {
                    call.respond(HttpStatusCode.OK, notificationService.getNotifications(callerId))
                } catch (e: Exception) {
                    call.application.log.error("GET /api/notifications failed for caller=$callerId", e)
                    call.respond(HttpStatusCode.InternalServerError, internalError("retrieve notifications"))
                }
            }

            /**
             * PATCH /api/notifications/read-all
             *
             * Marks all unread notifications for the authenticated user as read.
             * Registered BEFORE `{id}/read` so Ktor does not treat "read-all"
             * as a path parameter value.
             *
             * Responses:
             *   200 OK                  -- [MarkReadResponse] JSON
             *   401 Unauthorized        -- Invalid or missing JWT
             *   503 Service Unavailable -- Database not configured
             */
            patch("/read-all") {
                val callerId = call.requireAuthOrRespond() ?: return@patch
                if (!call.requireDatabaseOrRespond(databaseReady)) return@patch

                try {
                    call.respond(HttpStatusCode.OK, notificationService.markAllNotificationsRead(callerId))
                } catch (e: Exception) {
                    call.application.log.error("PATCH /api/notifications/read-all failed for caller=$callerId", e)
                    call.respond(HttpStatusCode.InternalServerError, internalError("mark notifications as read"))
                }
            }

            /**
             * PATCH /api/notifications/{id}/read
             *
             * Marks a single notification as read. Only the owner may mark it.
             *
             * Path parameter:
             *   id -- UUID of the notification to mark as read.
             *
             * Responses:
             *   200 OK                  -- [MarkReadResponse] JSON
             *   400 Bad Request         -- Malformed UUID in path parameter
             *   401 Unauthorized        -- Invalid or missing JWT
             *   404 Not Found           -- Notification not found or not owned by caller
             *   503 Service Unavailable -- Database not configured
             */
            patch("/{id}/read") {
                val callerId = call.requireAuthOrRespond() ?: return@patch
                if (!call.requireDatabaseOrRespond(databaseReady)) return@patch

                val notificationId = try {
                    UUID.fromString(call.parameters["id"])
                } catch (e: IllegalArgumentException) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(error = "bad_request", message = "Path parameter 'id' must be a valid UUID"),
                    )
                    return@patch
                }

                try {
                    when (val result = notificationService.markNotificationRead(callerId, notificationId)) {
                        is MarkNotificationReadResult.Success ->
                            call.respond(HttpStatusCode.OK, result.response)

                        is MarkNotificationReadResult.NotFound ->
                            call.respond(
                                HttpStatusCode.NotFound,
                                ErrorResponse(error = "not_found", message = "Notification not found"),
                            )
                    }
                } catch (e: Exception) {
                    call.application.log.error(
                        "PATCH /api/notifications/$notificationId/read failed for caller=$callerId", e
                    )
                    call.respond(HttpStatusCode.InternalServerError, internalError("mark notification as read"))
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/**
 * Extracts the authenticated caller ID, or responds with 401 and returns null.
 * Callers should `return@handler` when this returns null.
 */
private suspend fun RoutingCall.requireAuthOrRespond(): UUID? {
    val callerId = authenticatedUserId()
    if (callerId == null) {
        respond(
            HttpStatusCode.Unauthorized,
            ErrorResponse(error = "unauthorized", message = "Invalid authentication credentials"),
        )
    }
    return callerId
}

/**
 * Responds with 503 and returns false when the database is not ready.
 * Callers should `return@handler` when this returns false.
 */
private suspend fun RoutingCall.requireDatabaseOrRespond(databaseReady: Boolean): Boolean {
    if (!databaseReady) {
        respond(
            HttpStatusCode.ServiceUnavailable,
            ErrorResponse(error = "service_unavailable", message = "Database connection is not configured"),
        )
    }
    return databaseReady
}

/** Builds a generic internal-error response for the given [operation]. */
private fun internalError(operation: String) =
    ErrorResponse(error = "internal_server_error", message = "Failed to $operation")
