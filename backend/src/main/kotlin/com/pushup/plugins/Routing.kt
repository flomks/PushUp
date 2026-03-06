package com.pushup.plugins

import com.pushup.models.HealthResponse
import com.pushup.routes.statsRoutes
import com.pushup.routes.userRoutes
import com.pushup.service.StatsService
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.response.respond
import io.ktor.server.routing.get
import io.ktor.server.routing.routing

fun Application.configureRouting(
    statsService: StatsService = StatsService(),
    databaseReady: Boolean = true,
) {
    routing {
        get("/health") {
            call.respond(HttpStatusCode.OK, HealthResponse(status = "ok"))
        }

        userRoutes(databaseReady = databaseReady)
        statsRoutes(statsService)
    }
}
