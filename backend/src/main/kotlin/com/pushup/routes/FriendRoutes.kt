package com.pushup.routes

import com.pushup.models.ErrorResponse
import com.pushup.models.SendFriendRequestBody
import com.pushup.plugins.JWT_AUTH
import com.pushup.plugins.authenticatedUserId
import com.pushup.service.FriendshipService
import com.pushup.service.SendFriendRequestResult
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.log
import io.ktor.server.auth.authenticate
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import java.util.UUID

/**
 * Registers all /api/friends routes.
 *
 * Routes:
 *   POST /api/friends/request -- Sends a friend request from the authenticated
 *                                user to another user identified by receiver_id.
 *
 * @param friendshipService Service that handles friendship business logic.
 * @param databaseReady     Whether the database connection was successfully
 *                          initialised. When false, all DB-dependent endpoints
 *                          return 503 instead of an opaque 500.
 */
fun Route.friendRoutes(
    friendshipService: FriendshipService = FriendshipService(),
    databaseReady: Boolean = true,
) {
    authenticate(JWT_AUTH) {
        route("/api/friends") {

            /**
             * POST /api/friends/request
             *
             * Sends a friend request from the authenticated user to the user
             * identified by [SendFriendRequestBody.receiverId].
             *
             * Request body (JSON):
             * ```json
             * { "receiverId": "<uuid>" }
             * ```
             *
             * Responses:
             *   201 Created             -- [FriendshipResponse] JSON; request created
             *   400 Bad Request         -- Missing or malformed receiver_id
             *   401 Unauthorized        -- Invalid or missing JWT
             *   404 Not Found           -- Receiver user does not exist
             *   409 Conflict            -- Duplicate request or users are already friends
             *   422 Unprocessable       -- Requester tried to send a request to themselves
             *   503 Service Unavailable -- Database not configured
             */
            post("/request") {
                // ----------------------------------------------------------
                // Auth guard
                // ----------------------------------------------------------
                val requesterId = call.authenticatedUserId()
                if (requesterId == null) {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(
                            error   = "unauthorized",
                            message = "Invalid authentication credentials",
                        ),
                    )
                    return@post
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
                    return@post
                }

                // ----------------------------------------------------------
                // Parse and validate request body
                // ----------------------------------------------------------
                val body = try {
                    call.receive<SendFriendRequestBody>()
                } catch (e: Exception) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = "Request body must be JSON with a 'receiverId' field",
                        ),
                    )
                    return@post
                }

                val receiverId = try {
                    UUID.fromString(body.receiverId)
                } catch (e: IllegalArgumentException) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = "Invalid 'receiverId': must be a valid UUID",
                        ),
                    )
                    return@post
                }

                // ----------------------------------------------------------
                // Delegate to service
                // ----------------------------------------------------------
                try {
                    when (val result = friendshipService.sendFriendRequest(requesterId, receiverId)) {
                        is SendFriendRequestResult.Success -> {
                            call.respond(HttpStatusCode.Created, result.friendship)
                        }

                        is SendFriendRequestResult.SelfRequest -> {
                            call.respond(
                                HttpStatusCode.UnprocessableEntity,
                                ErrorResponse(
                                    error   = "self_request",
                                    message = "You cannot send a friend request to yourself",
                                ),
                            )
                        }

                        is SendFriendRequestResult.ReceiverNotFound -> {
                            call.respond(
                                HttpStatusCode.NotFound,
                                ErrorResponse(
                                    error   = "receiver_not_found",
                                    message = "The specified receiver does not exist",
                                ),
                            )
                        }

                        is SendFriendRequestResult.AlreadyExists -> {
                            val detail = when (result.existingStatus) {
                                "accepted" -> "You are already friends with this user"
                                "pending"  -> "A friend request is already pending between you and this user"
                                "declined" -> "A friend request between you and this user was previously declined"
                                else       -> "A friendship record already exists between you and this user"
                            }
                            call.respond(
                                HttpStatusCode.Conflict,
                                ErrorResponse(
                                    error   = "already_exists",
                                    message = detail,
                                ),
                            )
                        }
                    }
                } catch (e: Exception) {
                    call.application.log.error(
                        "Failed to send friend request from $requesterId to $receiverId", e
                    )
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to send friend request",
                        ),
                    )
                }
            }
        }
    }
}
