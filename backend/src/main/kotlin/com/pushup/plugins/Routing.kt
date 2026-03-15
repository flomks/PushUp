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

        // Friend code landing page: /friend/<CODE>
        //
        // Shown when someone taps a shared friend-code link.
        // Displays the code, an "Add Friend" button (opens the app via
        // custom scheme), and store download buttons.
        //
        // When Universal Links are active (Associated Domains + AASA),
        // iOS intercepts the https:// link before Safari loads this page
        // and opens the app directly -- this HTML is never shown.
        get("/friend/{code}") {
            val code      = call.parameters["code"]?.uppercase()?.filter { it.isLetterOrDigit() } ?: ""
            val formatted = code.chunked(4).joinToString(" ")
            val appScheme = "pushup://friend-code/$code"
            // Replace id0000000000 with the real App Store ID once published.
            val appStoreUrl  = "https://apps.apple.com/app/id0000000000"
            val playStoreUrl = "https://play.google.com/store/apps/details?id=com.flomks.pushup"

            call.respondText(
                contentType = ContentType.Text.Html,
                text = """
                    <!DOCTYPE html>
                    <html lang="en">
                    <head>
                      <meta charset="UTF-8">
                      <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
                      <title>Add Friend · PushUp</title>
                      <style>
                        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

                        :root {
                          --bg:      #0a0a0a;
                          --surface: #141414;
                          --border:  #222;
                          --text:    #f5f5f5;
                          --muted:   #888;
                          --accent:  #007AFF;
                          --radius:  16px;
                        }

                        html, body {
                          min-height: 100%;
                          background: var(--bg);
                          color: var(--text);
                          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                          display: flex;
                          align-items: center;
                          justify-content: center;
                          padding: 24px;
                        }

                        .card {
                          width: 100%;
                          max-width: 380px;
                          background: var(--surface);
                          border: 1px solid var(--border);
                          border-radius: 24px;
                          padding: 40px 32px 36px;
                          text-align: center;
                        }

                        .icon {
                          width: 72px; height: 72px;
                          background: linear-gradient(135deg, #1a1a2e, #16213e);
                          border-radius: 18px;
                          display: flex; align-items: center; justify-content: center;
                          margin: 0 auto 24px;
                          font-size: 36px;
                          border: 1px solid var(--border);
                        }

                        h1 {
                          font-size: 22px;
                          font-weight: 700;
                          letter-spacing: -0.3px;
                          margin-bottom: 6px;
                        }

                        .subtitle {
                          color: var(--muted);
                          font-size: 15px;
                          margin-bottom: 28px;
                          line-height: 1.4;
                        }

                        .code-box {
                          background: var(--bg);
                          border: 1px solid var(--border);
                          border-radius: var(--radius);
                          padding: 16px 20px;
                          margin-bottom: 28px;
                        }

                        .code-label {
                          font-size: 11px;
                          font-weight: 600;
                          letter-spacing: 1.2px;
                          text-transform: uppercase;
                          color: var(--muted);
                          margin-bottom: 6px;
                        }

                        .code-value {
                          font-family: "SF Mono", "Fira Code", monospace;
                          font-size: 28px;
                          font-weight: 700;
                          letter-spacing: 6px;
                          color: var(--text);
                        }

                        .btn {
                          display: block;
                          width: 100%;
                          padding: 15px 20px;
                          border-radius: var(--radius);
                          font-size: 16px;
                          font-weight: 600;
                          text-decoration: none;
                          cursor: pointer;
                          border: none;
                          transition: opacity .15s;
                        }
                        .btn:active { opacity: .75; }

                        .btn-primary {
                          background: var(--accent);
                          color: #fff;
                          margin-bottom: 10px;
                        }

                        .divider {
                          display: flex;
                          align-items: center;
                          gap: 10px;
                          margin: 20px 0 16px;
                          color: var(--muted);
                          font-size: 12px;
                        }
                        .divider::before, .divider::after {
                          content: "";
                          flex: 1;
                          height: 1px;
                          background: var(--border);
                        }

                        .store-row {
                          display: flex;
                          gap: 10px;
                        }

                        .btn-store {
                          flex: 1;
                          background: var(--bg);
                          border: 1px solid var(--border);
                          color: var(--text);
                          font-size: 13px;
                          padding: 12px 10px;
                          border-radius: var(--radius);
                          text-decoration: none;
                          display: flex;
                          flex-direction: column;
                          align-items: center;
                          gap: 4px;
                          transition: border-color .15s;
                        }
                        .btn-store:active { border-color: var(--accent); }

                        .store-icon { font-size: 20px; }
                        .store-label { font-size: 10px; color: var(--muted); font-weight: 500; }
                        .store-name  { font-size: 13px; font-weight: 600; }

                        .footer {
                          margin-top: 28px;
                          font-size: 12px;
                          color: var(--muted);
                        }
                      </style>
                    </head>
                    <body>
                      <div class="card">
                        <div class="icon">💪</div>

                        <h1>You've been invited!</h1>
                        <p class="subtitle">
                          Someone wants to add you as a friend on PushUp.<br>
                          Open the app to accept.
                        </p>

                        <div class="code-box">
                          <div class="code-label">Friend Code</div>
                          <div class="code-value">$formatted</div>
                        </div>

                        <a class="btn btn-primary" href="$appScheme">
                          Add Friend in PushUp
                        </a>

                        <div class="divider">Don't have the app?</div>

                        <div class="store-row">
                          <a class="btn-store" href="$appStoreUrl">
                            <span class="store-icon">🍎</span>
                            <span class="store-label">Download on the</span>
                            <span class="store-name">App Store</span>
                          </a>
                          <a class="btn-store" href="$playStoreUrl">
                            <span class="store-icon">▶</span>
                            <span class="store-label">Get it on</span>
                            <span class="store-name">Google Play</span>
                          </a>
                        </div>

                        <p class="footer">PushUp · Earn your screen time</p>
                      </div>
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
