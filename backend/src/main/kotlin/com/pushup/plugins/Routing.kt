package com.pushup.plugins

import com.pushup.models.HealthResponse
import com.pushup.routes.statsRoutes
import com.pushup.routes.userDataRoutes
import com.pushup.routes.userRoutes
import com.pushup.service.StatsService
import com.pushup.service.UserDataService
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.response.respond
import io.ktor.server.routing.get
import io.ktor.server.routing.head
import io.ktor.server.routing.routing

fun Application.configureRouting(
    statsService: StatsService = StatsService(),
    userDataService: UserDataService = UserDataService(statsService),
    databaseReady: Boolean = true,
) {
    routing {
        // GET and HEAD for /health -- Nginx, Docker healthcheck, and uptime
        // monitors commonly send HEAD requests to check if the server is alive.
        get("/health") {
            call.respond(HttpStatusCode.OK, HealthResponse(status = "ok"))
        }
        head("/health") {
            call.respond(HttpStatusCode.OK)
        }

        userRoutes(databaseReady = databaseReady)
        statsRoutes(statsService)
        userDataRoutes(userDataService, databaseReady = databaseReady)
    }
}
