package com.pushup.plugins

import com.pushup.models.ErrorResponse
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.application.log
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.response.respond

fun Application.configureStatusPages() {
    install(StatusPages) {
        exception<IllegalArgumentException> { call, cause ->
            // Log the full message server-side but return a generic message
            // to the client to avoid leaking internal details.
            call.application.log.warn("Bad request: ${cause.message}", cause)
            call.respond(
                HttpStatusCode.BadRequest,
                ErrorResponse(error = "bad_request", message = "Invalid request parameters"),
            )
        }
        exception<Throwable> { call, cause ->
            call.application.log.error("Unhandled exception", cause)
            call.respond(
                HttpStatusCode.InternalServerError,
                ErrorResponse(error = "internal_server_error", message = "An unexpected error occurred"),
            )
        }
        status(HttpStatusCode.NotFound) { call, status ->
            call.respond(status, ErrorResponse(error = "not_found", message = "Not found"))
        }
    }
}
