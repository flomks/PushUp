package com.pushup.plugins

import com.pushup.models.HealthResponse
import com.pushup.routes.activityStatsRoutes
import com.pushup.routes.deviceTokenRoutes
import com.pushup.routes.friendActivityStatsRoutes
import com.pushup.routes.friendCodeRoutes
import com.pushup.routes.friendRoutes
import com.pushup.routes.joggingStatsRoutes
import com.pushup.routes.statsRoutes
import com.pushup.routes.userDataRoutes
import com.pushup.routes.userRoutes
import com.pushup.routes.userSearchRoutes
import com.pushup.routes.usernameRoutes
import com.pushup.service.ActivityStatsService
import com.pushup.service.DeviceTokenService
import com.pushup.service.FriendActivityStatsService
import com.pushup.service.FriendCodeService
import com.pushup.service.FriendshipService
import com.pushup.service.JoggingStatsService
import com.pushup.service.StatsService
import com.pushup.service.UserDataService
import com.pushup.service.UserSearchService
import com.pushup.web.publicWebRoutes
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.response.respond
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
    routing {
        publicWebRoutes()

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
