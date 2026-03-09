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
import io.ktor.server.routing.get
import io.ktor.server.routing.patch
import io.ktor.server.routing.route
import java.util.UUID

/**
 * Registers all /api/notifications routes.
 *
 * Routes:
 *   GET   /api/notifications                  -- Returns all notifications for the caller.
 *   PATCH /api/notifications/{id}/read        -- Marks a single notification as read.
 *   PATCH /api/notifications/read-all         -- Marks all notifications as read.
 *
 * @param notificationService Service that handles notification business logic.
 * @param databaseReady       Whether the database connection was successfully
 *                            initialised. When false, all DB-dependent endpoints
 *                            return 503 instead of an opaque 500.
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
             * Returns all in-app notifications for the authenticated user, ordered
             * by creation time descending (newest first).
             *
             * Response body (JSON):
             * ```json
             * {
             *   "notifications": [
             *     {
             *       "id": "<uuid>",
             *       "type": "friend_request",
             *       "actorId": "<uuid>",
             *       "actorName": "Alice Smith",
             *       "payload": "{\"friendship_id\":\"<uuid>\"}",
             *       "isRead": false,
             *       "createdAt": "2026-03-09T12:00:00Z"
             *     }
             *   ],
             *   "total": 1,
             *   "unreadCount": 1
             * }
             * ```
             *
             * Responses:
             *   200 OK                  -- [NotificationsListResponse] JSON
             *   401 Unauthorized        -- Invalid or missing JWT
             *   503 Service Unavailable -- Database not configured
             */
            get {
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

                try {
                    val response = notificationService.getNotifications(callerId)
                    call.respond(HttpStatusCode.OK, response)
                } catch (e: Exception) {
                    call.application.log.error(
                        "Failed to retrieve notifications for caller=$callerId", e
                    )
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to retrieve notifications",
                        ),
                    )
                }
            }

            /**
             * PATCH /api/notifications/read-all
             *
             * Marks all unread notifications for the authenticated user as read.
             * Must be registered BEFORE the `{id}/read` route to avoid Ktor
             * treating "read-all" as an ID segment.
             *
             * Response body (JSON):
             * ```json
             * { "updatedCount": 3 }
             * ```
             *
             * Responses:
             *   200 OK                  -- [MarkReadResponse] JSON
             *   401 Unauthorized        -- Invalid or missing JWT
             *   503 Service Unavailable -- Database not configured
             */
            patch("/read-all") {
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

                try {
                    val response = notificationService.markAllNotificationsRead(callerId)
                    call.respond(HttpStatusCode.OK, response)
                } catch (e: Exception) {
                    call.application.log.error(
                        "Failed to mark all notifications as read for caller=$callerId", e
                    )
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to mark notifications as read",
                        ),
                    )
                }
            }

            /**
             * PATCH /api/notifications/{id}/read
             *
             * Marks a single notification as read. Only the owner of the
             * notification may mark it as read.
             *
             * Path parameter:
             *   id -- UUID of the notification to mark as read.
             *
             * Response body (JSON):
             * ```json
             * { "updatedCount": 1 }
             * ```
             *
             * Responses:
             *   200 OK                  -- [MarkReadResponse] JSON
             *   400 Bad Request         -- Malformed UUID in path parameter
             *   401 Unauthorized        -- Invalid or missing JWT
             *   404 Not Found           -- Notification not found or not owned by caller
             *   503 Service Unavailable -- Database not configured
             */
            patch("/{id}/read") {
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

                val notificationId = try {
                    UUID.fromString(call.parameters["id"])
                } catch (e: IllegalArgumentException) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = "Path parameter 'id' must be a valid UUID",
                        ),
                    )
                    return@patch
                }

                try {
                    when (val result = notificationService.markNotificationRead(callerId, notificationId)) {
                        is MarkNotificationReadResult.Success -> {
                            call.respond(HttpStatusCode.OK, result.response)
                        }

                        is MarkNotificationReadResult.NotFound -> {
                            call.respond(
                                HttpStatusCode.NotFound,
                                ErrorResponse(
                                    error   = "not_found",
                                    message = "Notification not found",
                                ),
                            )
                        }
                    }
                } catch (e: Exception) {
                    call.application.log.error(
                        "Failed to mark notification $notificationId as read for caller=$callerId", e
                    )
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to mark notification as read",
                        ),
                    )
                }
            }
        }
    }
}
