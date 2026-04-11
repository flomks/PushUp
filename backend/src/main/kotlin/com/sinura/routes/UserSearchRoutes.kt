package com.sinura.routes

import com.sinura.models.ErrorResponse
import com.sinura.plugins.JWT_AUTH
import com.sinura.plugins.authenticatedUserId
import com.sinura.service.UserSearchService
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.log
import io.ktor.server.auth.authenticate
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route

/**
 * Registers the GET /v1/users/search route.
 *
 * Searches for users by username or display name.  The authenticated caller
 * is excluded from the results.  Each result is annotated with the friendship
 * status between the caller and the matched user.
 *
 * Query parameters:
 *   q  (required) -- search term; minimum 2 characters
 *
 * Response shape:
 * ```json
 * {
 *   "results": [
 *     {
 *       "id": "uuid",
 *       "username": "john_doe",
 *       "displayName": "John Doe",
 *       "avatarUrl": "https://...",
 *       "friendshipStatus": "none" | "pending" | "friend"
 *     }
 *   ],
 *   "total": 1
 * }
 * ```
 *
 * HTTP responses:
 *   200 OK                  -- [UserSearchResponse] JSON (may have empty results list)
 *   400 Bad Request         -- Missing or too-short query parameter
 *   401 Unauthorized        -- Invalid or missing JWT
 *   503 Service Unavailable -- Database not configured
 */
fun Route.userSearchRoutes(
    userSearchService: UserSearchService = UserSearchService(),
    databaseReady: Boolean = true,
) {
    authenticate(JWT_AUTH) {
        route("/v1/users") {

            /**
             * GET /v1/users/search?q={query}
             *
             * Returns up to 20 users whose username or display name contains
             * the search term (case-insensitive substring match).
             *
             * The caller's own account is always excluded.
             * Users with a DECLINED (blocked) relationship are excluded.
             * Accepted friends are marked with friendshipStatus = "friend".
             * Users with a pending request are marked with friendshipStatus = "pending".
             */
            get("/search") {
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

                val query = call.request.queryParameters["q"]
                if (query.isNullOrBlank()) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = "Query parameter 'q' is required",
                        ),
                    )
                    return@get
                }

                if (query.length < UserSearchService.MIN_QUERY_LENGTH) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            error   = "bad_request",
                            message = "Query parameter 'q' must be at least " +
                                "${UserSearchService.MIN_QUERY_LENGTH} characters long",
                        ),
                    )
                    return@get
                }

                try {
                    val response = userSearchService.search(query = query, callerId = callerId)
                    call.respond(HttpStatusCode.OK, response)
                } catch (e: Exception) {
                    call.application.log.error(
                        "Failed to search users for caller=$callerId query='$query'", e
                    )
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                            error   = "internal_server_error",
                            message = "Failed to perform user search",
                        ),
                    )
                }
            }
        }
    }
}
