package com.pushup.routes

import com.pushup.models.ErrorResponse
import com.pushup.models.RespondFriendRequestBody
import com.pushup.models.SendFriendRequestBody
import com.pushup.plugins.FriendshipStatus
import com.pushup.plugins.JWT_AUTH
import com.pushup.plugins.authenticatedUserId
import com.pushup.service.FriendListFilter
import com.pushup.service.FriendshipService
import com.pushup.service.RemoveFriendResult
import com.pushup.service.RespondFriendRequestResult
import com.pushup.service.SendFriendRequestResult
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.log
import io.ktor.server.auth.authenticate
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.delete
import io.ktor.server.routing.get
import io.ktor.server.routing.patch
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import java.util.UUID

/**
 * Registers all /api/friends routes.
 *
 * Routes:
 *   GET    /api/friends                       -- Returns the caller's friends list.
 *                                                Optional query parameter:
 *                                                  ?status=accepted  (default) -- confirmed friends
 *                                                  ?status=incoming            -- pending requests received
 *                                                  ?status=outgoing            -- pending requests sent
 *   GET    /api/friends/requests/incoming     -- Returns incoming pending requests with friendship IDs.
 *   POST   /api/friends/request               -- Sends a friend request from the authenticated
 *                                                user to another user identified by receiver_id.
 *   PATCH  /api/friends/request/{id}          -- Allows the receiver to accept or decline a
 *                                                pending friend request.
 *   DELETE /api/friends/{id}                  -- Removes an accepted friendship between the
 *                                                authenticated user and the specified friend.
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
             * GET /api/friends?status={accepted|incoming|outgoing}
             *
             * Returns the friends list of the authenticated user.
             *
             * Query parameters:
             *   status (optional) -- one of:
             *     "accepted"  (default) -- confirmed friends (status = accepted)
             *     "incoming"            -- pending requests received by the caller
             *     "outgoing"            -- pending requests sent by the caller
             *
             * Response body (JSON):
             * ```json
             * {
             *   "friends": [
             *     {
             *       "id": "<uuid>",
             *       "username": "john_doe",
             *       "displayName": "John Doe",
             *       "avatarUrl": "https://..."
             *     }
             *   ],
             *   "total": 1
             * }
             * ```
             *
             * Responses:
             *   200 OK                  -- [FriendsListResponse] JSON
             *   400 Bad Request         -- Unknown value for the `status` query parameter
             *   401 Unauthorized        -- Invalid or missing JWT
             *   503 Service Unavailable -- Database not configured
             */
            get {
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
                // Parse and validate the optional ?status= query parameter
                // ----------------------------------------------------------
                val statusParam = call.request.queryParameters["status"]
                val filter = FriendListFilter.fromQueryParam(statusParam)
                if (filter == null) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = "Invalid 'status' parameter: must be 'accepted', 'incoming', or 'outgoing'",
                        ),
                    )
                    return@get
                }

                // ----------------------------------------------------------
                // Delegate to service
                // ----------------------------------------------------------
                try {
                    val response = friendshipService.getFriends(callerId, filter)
                    call.respond(HttpStatusCode.OK, response)
                } catch (e: Exception) {
                    call.application.log.error(
                        "Failed to retrieve friends list for caller=$callerId filter=$filter", e
                    )
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to retrieve friends list",
                        ),
                    )
                }
            }

            /**
             * GET /api/friends/requests/incoming
             *
             * Returns all incoming pending friend requests for the authenticated user.
             * Each entry includes the friendship row ID (needed to accept/decline) and
             * the requester's profile data.
             *
             * Response body (JSON):
             * ```json
             * {
             *   "requests": [
             *     {
             *       "friendshipId": "<uuid>",
             *       "requesterId":  "<uuid>",
             *       "username":     "john_doe",
             *       "displayName":  "John Doe",
             *       "avatarUrl":    null,
             *       "createdAt":    "2024-01-01T12:00:00Z"
             *     }
             *   ],
             *   "total": 1
             * }
             * ```
             *
             * Responses:
             *   200 OK                  -- [IncomingFriendRequestsResponse] JSON
             *   401 Unauthorized        -- Invalid or missing JWT
             *   503 Service Unavailable -- Database not configured
             */
            get("/requests/incoming") {
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
                    val response = friendshipService.getIncomingFriendRequests(callerId)
                    call.respond(HttpStatusCode.OK, response)
                } catch (e: Exception) {
                    call.application.log.error(
                        "Failed to retrieve incoming friend requests for caller=$callerId", e
                    )
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to retrieve incoming friend requests",
                        ),
                    )
                }
            }

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

            /**
             * DELETE /api/friends/{id}
             *
             * Removes the accepted friendship between the authenticated user and the
             * user identified by the `{id}` path parameter.
             *
             * Path parameter:
             *   id -- UUID of the friend's user account to remove.
             *
             * Responses:
             *   204 No Content          -- Friendship removed successfully
             *   400 Bad Request         -- Malformed UUID in path parameter
             *   401 Unauthorized        -- Invalid or missing JWT
             *   404 Not Found           -- No accepted friendship exists with this user
             *   422 Unprocessable       -- Caller tried to remove themselves
             *   503 Service Unavailable -- Database not configured
             */
            delete("/{id}") {
                val callerId = call.authenticatedUserId()
                if (callerId == null) {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(
                            error   = "unauthorized",
                            message = "Invalid authentication credentials",
                        ),
                    )
                    return@delete
                }

                if (!databaseReady) {
                    call.respond(
                        HttpStatusCode.ServiceUnavailable,
                        ErrorResponse(
                            error   = "service_unavailable",
                            message = "Database connection is not configured",
                        ),
                    )
                    return@delete
                }

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
                    return@delete
                }

                // Prevent self-removal
                if (callerId == friendId) {
                    call.respond(
                        HttpStatusCode.UnprocessableEntity,
                        ErrorResponse(
                            error   = "self_removal",
                            message = "You cannot remove yourself as a friend",
                        ),
                    )
                    return@delete
                }

                try {
                    when (friendshipService.removeFriend(callerId, friendId)) {
                        is RemoveFriendResult.Success    -> call.respond(HttpStatusCode.NoContent)
                        is RemoveFriendResult.NotFriends -> call.respond(
                            HttpStatusCode.NotFound,
                            ErrorResponse(
                                error   = "not_found",
                                message = "No accepted friendship exists with this user",
                            ),
                        )
                    }
                } catch (e: Exception) {
                    call.application.log.error(
                        "Failed to remove friend friendId=$friendId for caller=$callerId", e
                    )
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to remove friend",
                        ),
                    )
                }
            }

            /**
             * PATCH /api/friends/request/{id}
             *
             * Allows the receiver of a pending friend request to accept or decline it.
             * Only the receiver of the request is authorised to respond; the requester
             * and any other user will receive 401.
             *
             * Path parameter:
             *   id -- UUID of the friendship row to update.
             *
             * Request body (JSON):
             * ```json
             * { "status": "accepted" }   // or "declined"
             * ```
             *
             * Responses:
             *   200 OK                  -- [FriendshipResponse] JSON; status updated
             *   400 Bad Request         -- Missing/malformed body or invalid status value
             *   401 Unauthorized        -- Invalid/missing JWT, or caller is not the receiver
             *   404 Not Found           -- No friendship with the given ID exists
             *   409 Conflict            -- Request was already accepted or declined
             *   503 Service Unavailable -- Database not configured
             */
            patch("/request/{id}") {
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
                    return@patch
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
                    return@patch
                }

                // ----------------------------------------------------------
                // Parse and validate the {id} path parameter
                // ----------------------------------------------------------
                val friendshipId = try {
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

                // ----------------------------------------------------------
                // Parse and validate request body
                // ----------------------------------------------------------
                val body = try {
                    call.receive<RespondFriendRequestBody>()
                } catch (e: Exception) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = "Request body must be JSON with a 'status' field",
                        ),
                    )
                    return@patch
                }

                val newStatus = when (body.status.lowercase()) {
                    FriendshipStatus.ACCEPTED.toDbValue() -> FriendshipStatus.ACCEPTED
                    FriendshipStatus.DECLINED.toDbValue() -> FriendshipStatus.DECLINED
                    else -> {
                        call.respond(
                            HttpStatusCode.BadRequest,
                            ErrorResponse(
                                error   = "bad_request",
                                message = "Invalid 'status': must be 'accepted' or 'declined'",
                            ),
                        )
                        return@patch
                    }
                }

                // ----------------------------------------------------------
                // Delegate to service
                // ----------------------------------------------------------
                try {
                    when (val result = friendshipService.respondToFriendRequest(callerId, friendshipId, newStatus)) {
                        is RespondFriendRequestResult.Success -> {
                            call.respond(HttpStatusCode.OK, result.friendship)
                        }

                        is RespondFriendRequestResult.NotFound -> {
                            call.respond(
                                HttpStatusCode.NotFound,
                                ErrorResponse(
                                    error   = "not_found",
                                    message = "Friend request not found",
                                ),
                            )
                        }

                        is RespondFriendRequestResult.Forbidden -> {
                            // Return 401 (not 403) as per the acceptance criteria:
                            // "Nur der Empfänger kann die Anfrage beantworten (401 sonst)"
                            call.respond(
                                HttpStatusCode.Unauthorized,
                                ErrorResponse(
                                    error   = "unauthorized",
                                    message = "You are not the receiver of this friend request",
                                ),
                            )
                        }

                        is RespondFriendRequestResult.AlreadyResponded -> {
                            call.respond(
                                HttpStatusCode.Conflict,
                                ErrorResponse(
                                    error   = "already_responded",
                                    message = "This friend request has already been ${result.currentStatus}",
                                ),
                            )
                        }
                    }
                } catch (e: Exception) {
                    call.application.log.error(
                        "Failed to respond to friend request $friendshipId for caller $callerId", e
                    )
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to update friend request",
                        ),
                    )
                }
            }
        }
    }
}
