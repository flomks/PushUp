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
                    "appID": "2986PL676H.com.flomks.pushup",
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
        //
        // Strategy:
        //   1. JavaScript immediately tries to open pushup://friend-code/<CODE>
        //   2. A 1500ms timer fires -- if the app opened, the page is hidden
        //      and the timer never redirects. If the app is NOT installed,
        //      Safari cannot open the custom scheme and the timer redirects
        //      straight to the App Store.
        //   3. The user sees only a brief loading spinner -- no ugly web page.
        //
        // When Universal Links work (app installed + Associated Domains active),
        // iOS intercepts the https:// link BEFORE the browser even loads this
        // page, so this HTML is never shown at all.
        get("/friend/{code}") {
            val code       = call.parameters["code"]?.uppercase()?.filter { it.isLetterOrDigit() } ?: ""
            val appScheme  = "pushup://friend-code/$code"
            // Replace with the real App Store ID once the app is published.
            val appStoreUrl = "https://apps.apple.com/app/id0000000000"

            call.respondText(
                contentType = ContentType.Text.Html,
                text = """
                    <!DOCTYPE html>
                    <html lang="en">
                    <head>
                      <meta charset="UTF-8">
                      <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
                      <title>Opening PushUp…</title>
                      <style>
                        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
                        html, body {
                          height: 100%; background: #000; color: #fff;
                          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                          display: flex; align-items: center; justify-content: center;
                        }
                        .wrap { text-align: center; padding: 24px; }
                        .spinner {
                          width: 48px; height: 48px; border-radius: 50%;
                          border: 4px solid rgba(255,255,255,.15);
                          border-top-color: #007AFF;
                          animation: spin .8s linear infinite;
                          margin: 0 auto 24px;
                        }
                        @keyframes spin { to { transform: rotate(360deg); } }
                        p { color: rgba(255,255,255,.5); font-size: 15px; }
                      </style>
                    </head>
                    <body>
                      <div class="wrap">
                        <div class="spinner"></div>
                        <p>Opening PushUp…</p>
                      </div>
                      <script>
                        // 1. Try to open the app via custom scheme.
                        window.location.href = '$appScheme';

                        // 2. If the app is not installed, the browser stays on this
                        //    page and the timer fires -> redirect to App Store.
                        //    If the app DID open, the page goes to background and
                        //    the timer is irrelevant (never causes a redirect).
                        var t = setTimeout(function() {
                          window.location.replace('$appStoreUrl');
                        }, 1500);

                        // 3. Cancel the timer if the user comes back to the page
                        //    (e.g. they opened the app and then returned to Safari).
                        document.addEventListener('visibilitychange', function() {
                          if (document.visibilityState === 'hidden') {
                            clearTimeout(t);
                          }
                        });
                      </script>
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
