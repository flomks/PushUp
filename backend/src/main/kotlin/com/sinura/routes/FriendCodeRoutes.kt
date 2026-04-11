package com.sinura.routes

import com.sinura.models.ErrorResponse
import com.sinura.models.UpdateFriendCodePrivacyRequest
import com.sinura.models.UseFriendCodeRequest
import com.sinura.plugins.JWT_AUTH
import com.sinura.plugins.authenticatedUserId
import com.sinura.service.FriendCodeService
import com.sinura.service.GetOrCreateFriendCodeResult
import com.sinura.service.ResetCodeResult
import com.sinura.service.UpdatePrivacyResult
import com.sinura.service.UseFriendCodeResult
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.log
import io.ktor.server.auth.authenticate
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.patch
import io.ktor.server.routing.post
import io.ktor.server.routing.route

/**
 * Registers all /v1/friend-code routes.
 *
 * Routes:
 *   GET    /v1/friend-code              -- Returns (or creates) the caller's friend code.
 *   PATCH  /v1/friend-code/privacy      -- Updates the privacy setting of the caller's code.
 *   POST   /v1/friend-code/reset        -- Generates a new random code for the caller.
 *   POST   /v1/friend-code/use          -- Uses a friend code to add or request a friend.
 *
 * All routes require a valid JWT (Bearer token).
 *
 * @param friendCodeService Service that handles friend code business logic.
 * @param databaseReady     Whether the database connection was successfully initialised.
 */
fun Route.friendCodeRoutes(
    friendCodeService: FriendCodeService = FriendCodeService(),
    databaseReady: Boolean = true,
) {
    authenticate(JWT_AUTH) {
        route("/v1/friend-code") {

            /**
             * GET /v1/friend-code
             *
             * Returns the authenticated user's friend code. If the user does not yet
             * have a code, one is generated automatically with privacy = require_approval.
             *
             * Response body (JSON):
             * ```json
             * {
             *   "code":      "AB3X7K2M",
             *   "privacy":   "require_approval",
             *   "deepLink":  "pushup://friend-code/AB3X7K2M",
             *   "createdAt": "2026-03-15T12:00:00Z",
             *   "updatedAt": "2026-03-15T12:00:00Z"
             * }
             * ```
             *
             * Responses:
             *   200 OK                  -- [FriendCodeResponse] JSON
             *   401 Unauthorized        -- Invalid or missing JWT
             *   503 Service Unavailable -- Database not configured
             */
            get {
                val callerId = call.authenticatedUserId() ?: run {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(error = "unauthorized", message = "Invalid authentication credentials"),
                    )
                    return@get
                }

                if (!databaseReady) {
                    call.respond(
                        HttpStatusCode.ServiceUnavailable,
                        ErrorResponse(error = "service_unavailable", message = "Database connection is not configured"),
                    )
                    return@get
                }

                try {
                    when (val result = friendCodeService.getOrCreateFriendCode(callerId)) {
                        is GetOrCreateFriendCodeResult.Success ->
                            call.respond(HttpStatusCode.OK, result.response)

                        is GetOrCreateFriendCodeResult.UserNotFound ->
                            call.respond(
                                HttpStatusCode.NotFound,
                                ErrorResponse(error = "user_not_found", message = "Authenticated user not found"),
                            )
                    }
                } catch (e: Exception) {
                    call.application.log.error("Failed to get/create friend code for caller=$callerId", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(error = "internal_server_error", message = "Failed to retrieve friend code"),
                    )
                }
            }

            /**
             * PATCH /v1/friend-code/privacy
             *
             * Updates the privacy setting of the authenticated user's friend code.
             * Creates the code first if it does not yet exist.
             *
             * Request body (JSON):
             * ```json
             * { "privacy": "auto_accept" }   // or "require_approval" | "inactive"
             * ```
             *
             * Responses:
             *   200 OK                  -- [FriendCodeResponse] JSON with updated privacy
             *   400 Bad Request         -- Missing/malformed body or invalid privacy value
             *   401 Unauthorized        -- Invalid or missing JWT
             *   404 Not Found           -- Caller has no friend code yet (create one first)
             *   503 Service Unavailable -- Database not configured
             */
            patch("/privacy") {
                val callerId = call.authenticatedUserId() ?: run {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(error = "unauthorized", message = "Invalid authentication credentials"),
                    )
                    return@patch
                }

                if (!databaseReady) {
                    call.respond(
                        HttpStatusCode.ServiceUnavailable,
                        ErrorResponse(error = "service_unavailable", message = "Database connection is not configured"),
                    )
                    return@patch
                }

                val body = try {
                    call.receive<UpdateFriendCodePrivacyRequest>()
                } catch (e: Exception) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(error = "bad_request", message = "Request body must be JSON with a 'privacy' field"),
                    )
                    return@patch
                }

                try {
                    when (val result = friendCodeService.updatePrivacy(callerId, body.privacy)) {
                        is UpdatePrivacyResult.Success ->
                            call.respond(HttpStatusCode.OK, result.response)

                        is UpdatePrivacyResult.NotFound ->
                            call.respond(
                                HttpStatusCode.NotFound,
                                ErrorResponse(
                                    error   = "not_found",
                                    message = "You do not have a friend code yet. Call GET /v1/friend-code to create one.",
                                ),
                            )

                        is UpdatePrivacyResult.InvalidPrivacy ->
                            call.respond(
                                HttpStatusCode.BadRequest,
                                ErrorResponse(
                                    error   = "bad_request",
                                    message = "Invalid 'privacy' value '${result.value}': must be 'auto_accept', 'require_approval', or 'inactive'",
                                ),
                            )
                    }
                } catch (e: Exception) {
                    call.application.log.error("Failed to update friend code privacy for caller=$callerId", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(error = "internal_server_error", message = "Failed to update privacy setting"),
                    )
                }
            }

            /**
             * POST /v1/friend-code/reset
             *
             * Generates a new random code for the authenticated user, invalidating the
             * previous one. Creates the code row if it does not yet exist.
             *
             * No request body required.
             *
             * Responses:
             *   200 OK                  -- [FriendCodeResponse] JSON with the new code
             *   401 Unauthorized        -- Invalid or missing JWT
             *   503 Service Unavailable -- Database not configured
             */
            post("/reset") {
                val callerId = call.authenticatedUserId() ?: run {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(error = "unauthorized", message = "Invalid authentication credentials"),
                    )
                    return@post
                }

                if (!databaseReady) {
                    call.respond(
                        HttpStatusCode.ServiceUnavailable,
                        ErrorResponse(error = "service_unavailable", message = "Database connection is not configured"),
                    )
                    return@post
                }

                try {
                    when (val result = friendCodeService.resetCode(callerId)) {
                        is ResetCodeResult.Success ->
                            call.respond(HttpStatusCode.OK, result.response)

                        is ResetCodeResult.UserNotFound ->
                            call.respond(
                                HttpStatusCode.NotFound,
                                ErrorResponse(error = "user_not_found", message = "Authenticated user not found"),
                            )
                    }
                } catch (e: Exception) {
                    call.application.log.error("Failed to reset friend code for caller=$callerId", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(error = "internal_server_error", message = "Failed to reset friend code"),
                    )
                }
            }

            /**
             * POST /v1/friend-code/use
             *
             * Uses a friend code entered or scanned by the authenticated user.
             *
             * Behaviour depends on the code owner's privacy setting:
             * - auto_accept      -> friendship is created immediately (result = "added")
             * - require_approval -> a pending friend request is created (result = "pending")
             * - inactive         -> 410 Gone
             *
             * Request body (JSON):
             * ```json
             * { "code": "AB3X7K2M" }
             * ```
             *
             * Response body (JSON):
             * ```json
             * {
             *   "result": "added",
             *   "ownerProfile": { "id": "...", "username": "...", ... },
             *   "friendship": { "id": "...", "status": "accepted", ... }
             * }
             * ```
             *
             * Responses:
             *   200 OK                  -- [UseFriendCodeResponse] JSON
             *   400 Bad Request         -- Missing/malformed body
             *   401 Unauthorized        -- Invalid or missing JWT
             *   404 Not Found           -- Code does not exist
             *   409 Conflict            -- Already friends or request already pending
             *   410 Gone                -- Code is inactive
             *   422 Unprocessable       -- Caller tried to use their own code
             *   503 Service Unavailable -- Database not configured
             */
            post("/use") {
                val callerId = call.authenticatedUserId() ?: run {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(error = "unauthorized", message = "Invalid authentication credentials"),
                    )
                    return@post
                }

                if (!databaseReady) {
                    call.respond(
                        HttpStatusCode.ServiceUnavailable,
                        ErrorResponse(error = "service_unavailable", message = "Database connection is not configured"),
                    )
                    return@post
                }

                val body = try {
                    call.receive<UseFriendCodeRequest>()
                } catch (e: Exception) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(error = "bad_request", message = "Request body must be JSON with a 'code' field"),
                    )
                    return@post
                }

                if (body.code.isBlank()) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(error = "bad_request", message = "The 'code' field must not be empty"),
                    )
                    return@post
                }

                try {
                    when (val result = friendCodeService.useFriendCode(callerId, body.code)) {
                        is UseFriendCodeResult.Added ->
                            call.respond(HttpStatusCode.OK, result.response)

                        is UseFriendCodeResult.Pending ->
                            call.respond(HttpStatusCode.OK, result.response)

                        is UseFriendCodeResult.CodeNotFound ->
                            call.respond(
                                HttpStatusCode.NotFound,
                                ErrorResponse(error = "code_not_found", message = "The friend code '${body.code}' does not exist"),
                            )

                        is UseFriendCodeResult.CodeInactive ->
                            call.respond(
                                HttpStatusCode.Gone,
                                ErrorResponse(error = "code_inactive", message = "This friend code is currently inactive"),
                            )

                        is UseFriendCodeResult.SelfUse ->
                            call.respond(
                                HttpStatusCode.UnprocessableEntity,
                                ErrorResponse(error = "self_use", message = "You cannot use your own friend code"),
                            )

                        is UseFriendCodeResult.AlreadyFriends -> {
                            val detail = when (result.existingStatus) {
                                "accepted" -> "You are already friends with this user"
                                "pending"  -> "A friend request is already pending between you and this user"
                                else       -> "A friendship record already exists between you and this user"
                            }
                            call.respond(
                                HttpStatusCode.Conflict,
                                ErrorResponse(error = "already_exists", message = detail),
                            )
                        }
                    }
                } catch (e: Exception) {
                    call.application.log.error("Failed to use friend code '${body.code}' for caller=$callerId", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(error = "internal_server_error", message = "Failed to use friend code"),
                    )
                }
            }
        }
    }
}
