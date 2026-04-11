package com.sinura.plugins

import com.sinura.models.HealthResponse
import com.sinura.routes.activityStatsRoutes
import com.sinura.routes.deviceTokenRoutes
import com.sinura.routes.friendActivityStatsRoutes
import com.sinura.routes.friendCodeRoutes
import com.sinura.routes.friendRoutes
import com.sinura.routes.joggingStatsRoutes
import com.sinura.routes.statsRoutes
import com.sinura.routes.userDataRoutes
import com.sinura.routes.userRoutes
import com.sinura.routes.userSearchRoutes
import com.sinura.routes.usernameRoutes
import com.sinura.service.ActivityStatsService
import com.sinura.service.DeviceTokenService
import com.sinura.service.FriendActivityStatsService
import com.sinura.service.FriendCodeService
import com.sinura.service.FriendshipService
import com.sinura.service.JoggingStatsService
import com.sinura.service.StatsService
import com.sinura.service.UserDataService
import com.sinura.service.UserSearchService
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.plugins.swagger.swaggerUI
import io.ktor.server.response.respond
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.head
import io.ktor.server.routing.routing

fun Application.configureRouting(
    statsService: StatsService = StatsService(),
    activityStatsService: ActivityStatsService = ActivityStatsService(),
    userDataService: UserDataService = UserDataService(statsService),
    userSearchService: UserSearchService = UserSearchService(),
    deviceTokenService: DeviceTokenService = DeviceTokenService(),
    friendshipService: FriendshipService = FriendshipService(deviceTokenService),
    friendActivityStatsService: FriendActivityStatsService = FriendActivityStatsService(),
    friendCodeService: FriendCodeService = FriendCodeService(deviceTokenService),
    joggingStatsService: JoggingStatsService = JoggingStatsService(),
    databaseReady: Boolean = true,
) {
    val aasa = """
        {
          "applinks": {
            "apps": [],
            "details": [
              {
                "appID": "2986PL676H.com.flomks.sinura",
                "paths": [ "/friend/*" ]
              }
            ]
          }
        }
    """.trimIndent()

    routing {
        swaggerUI(path = "swagger", swaggerFile = "openapi.yaml")

        get("/.well-known/apple-app-site-association") {
            call.respondText(aasa, ContentType.Application.Json)
        }
        get("/apple-app-site-association") {
            call.respondText(aasa, ContentType.Application.Json)
        }

        get("/health") {
            call.respond(HttpStatusCode.OK, HealthResponse(status = "ok"))
        }
        head("/health") {
            call.respond(HttpStatusCode.OK)
        }

        userRoutes(databaseReady = databaseReady)
        statsRoutes(statsService)
        userDataRoutes(userDataService, databaseReady = databaseReady)
        userSearchRoutes(userSearchService, databaseReady = databaseReady)
        usernameRoutes(databaseReady = databaseReady)
        deviceTokenRoutes(deviceTokenService, databaseReady = databaseReady)
        friendRoutes(friendshipService, databaseReady = databaseReady)
        friendActivityStatsRoutes(friendActivityStatsService, databaseReady = databaseReady)
        friendCodeRoutes(friendCodeService, databaseReady = databaseReady)
        joggingStatsRoutes(joggingStatsService)
        activityStatsRoutes(activityStatsService)
    }
}
