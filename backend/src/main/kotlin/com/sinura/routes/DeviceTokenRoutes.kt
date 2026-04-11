package com.sinura.routes

import com.sinura.models.ErrorResponse
import com.sinura.models.RegisterDeviceTokenRequest
import com.sinura.models.RegisterDeviceTokenResponse
import com.sinura.plugins.JWT_AUTH
import com.sinura.plugins.authenticatedUserId
import com.sinura.service.DeviceTokenService
import com.sinura.service.UserNotFoundException
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.log
import io.ktor.server.auth.authenticate
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.post
import io.ktor.server.routing.route

/**
 * Registers the POST /v1/device-token route.
 *
 * The iOS app calls this endpoint after every successful login and on each
 * app launch (when the token may have been rotated by Apple). The backend
 * stores the token in [DeviceTokens] and uses it to deliver APNs pushes.
 *
 * Route:
 *   POST /v1/device-token
 *     Body: { "token": "<hex>", "platform": "apns" }
 *     Response 200: { "success": true }
 *
 * @param deviceTokenService Service that manages device token persistence.
 * @param databaseReady      Whether the database connection is available.
 */
fun Route.deviceTokenRoutes(
    deviceTokenService: DeviceTokenService = DeviceTokenService(),
    databaseReady: Boolean = true,
) {
    authenticate(JWT_AUTH) {
        route("/v1/device-token") {

            /**
             * POST /v1/device-token
             *
             * Registers or refreshes the caller's APNs device token.
             *
             * Responses:
             *   200 OK                  -- Token stored successfully
             *   400 Bad Request         -- Missing or empty token field
             *   401 Unauthorized        -- Invalid or missing JWT
             *   503 Service Unavailable -- Database not configured
             */
            post {
                val userId = call.authenticatedUserId()
                if (userId == null) {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(
                            error   = "unauthorized",
                            message = "Invalid authentication credentials",
                        ),
                    )
                    return@post
                }

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

                val body = try {
                    call.receive<RegisterDeviceTokenRequest>()
                } catch (e: Exception) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = "Request body must be JSON with a 'token' field",
                        ),
                    )
                    return@post
                }

                if (body.token.isBlank()) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = "'token' must not be empty",
                        ),
                    )
                    return@post
                }

                try {
                    deviceTokenService.upsertToken(
                        userId   = userId,
                        token    = body.token,
                        platform = body.platform.ifBlank { "apns" },
                    )
                    call.respond(HttpStatusCode.OK, RegisterDeviceTokenResponse(success = true))
                } catch (e: UserNotFoundException) {
                    // The JWT was valid but the user row no longer exists in the
                    // database (e.g. deleted via the Supabase dashboard). Return
                    // 404 so the client knows to re-authenticate rather than retry.
                    call.application.log.warn(
                        "Device token registration skipped: user=$userId not found in database. " +
                            "The user may have been deleted while the device still holds a valid JWT."
                    )
                    call.respond(
                        HttpStatusCode.NotFound,
                        ErrorResponse(
                            error   = "user_not_found",
                            message = "No user profile found. Please sign in again.",
                        ),
                    )
                } catch (e: Exception) {
                    call.application.log.error(
                        "Failed to register device token for user=$userId", e
                    )
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to register device token",
                        ),
                    )
                }
            }
        }
    }
}
