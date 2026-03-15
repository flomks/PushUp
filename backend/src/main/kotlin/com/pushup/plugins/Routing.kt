package com.pushup.plugins

import com.pushup.models.HealthResponse
import com.pushup.routes.deviceTokenRoutes
import com.pushup.routes.friendActivityStatsRoutes
import com.pushup.routes.friendCodeRoutes
import com.pushup.routes.friendRoutes
import com.pushup.routes.statsRoutes
import com.pushup.routes.userDataRoutes
import com.pushup.routes.userRoutes
import com.pushup.routes.userSearchRoutes
import com.pushup.routes.usernameRoutes
import com.pushup.service.DeviceTokenService
import com.pushup.service.FriendActivityStatsService
import com.pushup.service.FriendCodeService
import com.pushup.service.FriendshipService
import com.pushup.service.StatsService
import com.pushup.service.UserDataService
import com.pushup.service.UserSearchService
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.response.respond
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.head
import io.ktor.server.routing.routing

fun Application.configureRouting(
    statsService: StatsService = StatsService(),
    userDataService: UserDataService = UserDataService(statsService),
    userSearchService: UserSearchService = UserSearchService(),
    deviceTokenService: DeviceTokenService = DeviceTokenService(),
    friendshipService: FriendshipService = FriendshipService(deviceTokenService),
    friendActivityStatsService: FriendActivityStatsService = FriendActivityStatsService(),
    friendCodeService: FriendCodeService = FriendCodeService(deviceTokenService),
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

        // -----------------------------------------------------------------------
        // Universal Links: Apple App Site Association
        //
        // iOS fetches this file when the app is installed to verify that
        // https://pushup.weareo.fun/friend/<CODE> should open the app.
        //
        // Must be served at BOTH paths (Apple checks both):
        //   /.well-known/apple-app-site-association
        //   /apple-app-site-association
        //
        // Content-Type must be application/json (not .json extension).
        // -----------------------------------------------------------------------
        val aasa = """
            {
              "applinks": {
                "apps": [],
                "details": [
                  {
                    "appID": "XXXXXXXXXX.com.flomks.pushup",
                    "paths": [ "/friend/*" ]
                  }
                ]
              }
            }
        """.trimIndent()

        get("/.well-known/apple-app-site-association") {
            call.respondText(aasa, ContentType.Application.Json)
        }
        get("/apple-app-site-association") {
            call.respondText(aasa, ContentType.Application.Json)
        }

        // Universal Link landing page: /friend/<CODE>
        // When the app is NOT installed, this shows a web page with an
        // App Store link. When installed, iOS intercepts before this runs.
        get("/friend/{code}") {
            val code = call.parameters["code"]?.uppercase() ?: ""
            call.respondText(
                contentType = ContentType.Text.Html,
                text = """
                    <!DOCTYPE html>
                    <html lang="en">
                    <head>
                      <meta charset="UTF-8">
                      <meta name="viewport" content="width=device-width, initial-scale=1">
                      <title>Add Friend on PushUp</title>
                      <style>
                        body { font-family: -apple-system, sans-serif; text-align: center;
                               padding: 60px 24px; background: #0f0f0f; color: #fff; }
                        h1   { font-size: 28px; font-weight: 700; margin-bottom: 8px; }
                        p    { color: #aaa; margin-bottom: 32px; }
                        .code { font-family: monospace; font-size: 32px; font-weight: 700;
                                letter-spacing: 6px; background: #1c1c1e; padding: 16px 24px;
                                border-radius: 12px; display: inline-block; margin-bottom: 32px; }
                        a.btn { display: inline-block; background: #007AFF; color: #fff;
                                padding: 16px 32px; border-radius: 14px; text-decoration: none;
                                font-size: 17px; font-weight: 600; }
                      </style>
                    </head>
                    <body>
                      <h1>Add me on PushUp</h1>
                      <p>Open the app and enter this friend code:</p>
                      <div class="code">${code.chunked(4).joinToString(" ")}</div>
                      <br>
                      <a class="btn" href="pushup://friend-code/$code">Open in PushUp</a>
                      <br><br>
                      <p style="font-size:13px">Don't have PushUp yet?
                        <a href="https://apps.apple.com/app/id0000000000" style="color:#007AFF">
                          Download on the App Store
                        </a>
                      </p>
                    </body>
                    </html>
                """.trimIndent()
            )
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
    }
}
