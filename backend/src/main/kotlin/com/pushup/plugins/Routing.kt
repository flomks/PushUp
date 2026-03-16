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
                          --accent:  #3B82F6;
                          --accent2: #8B5CF6;
                          --text:    #f0f0f8;
                          --muted:   rgba(240,240,248,.45);
                          --card:    rgba(255,255,255,.05);
                          --border:  rgba(255,255,255,.09);
                          --r-lg:    24px;
                          --r-md:    16px;
                          --r-sm:    12px;
                        }

                        /* 100dvh = dynamic viewport height, works correctly on
                           iOS Safari where 100vh includes the browser chrome */
                        html, body { height: 100%; }

                        body {
                          min-height: 100dvh;
                          font-family: -apple-system, BlinkMacSystemFont, "Inter", "Segoe UI", sans-serif;
                          color: var(--text);
                          display: flex;
                          flex-direction: column;
                          align-items: center;
                          justify-content: center;
                          padding: 32px 20px 48px;
                          /* background-attachment: fixed keeps the gradient
                             from scrolling on mobile when content overflows */
                          background:
                            radial-gradient(ellipse 90% 55% at 50% -5%,  rgba(59,130,246,.22) 0%, transparent 65%),
                            radial-gradient(ellipse 70% 50% at 85% 105%, rgba(139,92,246,.18) 0%, transparent 65%),
                            radial-gradient(ellipse 50% 40% at 10% 90%,  rgba(59,130,246,.10) 0%, transparent 60%),
                            #07070f;
                          background-attachment: fixed;
                        }

                        /* ── Wordmark ── */
                        .wordmark {
                          display: flex;
                          align-items: center;
                          gap: 8px;
                          font-size: 13px;
                          font-weight: 800;
                          letter-spacing: 2.5px;
                          text-transform: uppercase;
                          color: var(--muted);
                          margin-bottom: 36px;
                        }
                        .wordmark-dot {
                          width: 7px; height: 7px;
                          border-radius: 50%;
                          background: linear-gradient(135deg, var(--accent), var(--accent2));
                        }

                        /* ── Card ── */
                        .card {
                          width: 100%;
                          max-width: 400px;
                          background: var(--card);
                          border: 1px solid var(--border);
                          border-radius: var(--r-lg);
                          padding: 44px 32px 40px;
                          text-align: center;
                          backdrop-filter: blur(24px);
                          -webkit-backdrop-filter: blur(24px);
                          box-shadow:
                            0 0 0 1px rgba(255,255,255,.04) inset,
                            0 40px 80px rgba(0,0,0,.55),
                            0 0 120px rgba(59,130,246,.06);
                        }

                        /* ── App icon ── */
                        .app-icon {
                          width: 84px; height: 84px;
                          background: linear-gradient(145deg, #1d4ed8 0%, #7c3aed 100%);
                          border-radius: 22px;
                          display: flex; align-items: center; justify-content: center;
                          margin: 0 auto 28px;
                          font-size: 40px;
                          box-shadow:
                            0 8px 32px rgba(59,130,246,.4),
                            0 0 0 1px rgba(255,255,255,.12) inset;
                        }

                        /* ── Headline ── */
                        h1 {
                          font-size: 26px;
                          font-weight: 800;
                          letter-spacing: -0.6px;
                          line-height: 1.15;
                          margin-bottom: 10px;
                          background: linear-gradient(160deg, #fff 40%, rgba(255,255,255,.55));
                          -webkit-background-clip: text;
                          -webkit-text-fill-color: transparent;
                          background-clip: text;
                        }

                        .subtitle {
                          color: var(--muted);
                          font-size: 15px;
                          line-height: 1.55;
                          margin-bottom: 36px;
                        }

                        /* ── Friend code box ── */
                        .code-box {
                          background: rgba(59,130,246,.07);
                          border: 1px solid rgba(59,130,246,.22);
                          border-radius: var(--r-md);
                          padding: 20px 24px 18px;
                          margin-bottom: 28px;
                          position: relative;
                          overflow: hidden;
                        }
                        .code-box::before {
                          content: "";
                          position: absolute;
                          inset: 0;
                          background: radial-gradient(ellipse 80% 60% at 50% 0%, rgba(59,130,246,.12), transparent);
                          pointer-events: none;
                        }

                        .code-label {
                          font-size: 10px;
                          font-weight: 700;
                          letter-spacing: 2px;
                          text-transform: uppercase;
                          color: var(--accent);
                          margin-bottom: 10px;
                        }

                        .code-value {
                          font-family: "SF Mono", "Fira Code", "Cascadia Code", ui-monospace, monospace;
                          font-size: 32px;
                          font-weight: 700;
                          letter-spacing: 9px;
                          color: #fff;
                          text-shadow: 0 0 28px rgba(59,130,246,.5);
                        }

                        /* ── Primary CTA ── */
                        .btn-primary {
                          display: flex;
                          align-items: center;
                          justify-content: center;
                          gap: 9px;
                          width: 100%;
                          padding: 17px 20px;
                          border-radius: var(--r-md);
                          font-size: 16px;
                          font-weight: 700;
                          letter-spacing: -.1px;
                          text-decoration: none;
                          color: #fff;
                          background: linear-gradient(135deg, var(--accent) 0%, var(--accent2) 100%);
                          box-shadow:
                            0 4px 28px rgba(59,130,246,.38),
                            0 0 0 1px rgba(255,255,255,.1) inset;
                          transition: transform .15s ease, box-shadow .15s ease;
                          -webkit-tap-highlight-color: transparent;
                        }
                        .btn-primary:active {
                          transform: scale(.97);
                          box-shadow: 0 2px 14px rgba(59,130,246,.25);
                        }

                        /* ── Divider ── */
                        .divider {
                          display: flex;
                          align-items: center;
                          gap: 12px;
                          margin: 28px 0 22px;
                          color: var(--muted);
                          font-size: 12px;
                          font-weight: 500;
                          letter-spacing: .4px;
                        }
                        .divider::before, .divider::after {
                          content: "";
                          flex: 1;
                          height: 1px;
                          background: var(--border);
                        }

                        /* ── Store badges ── */
                        .store-row { display: flex; gap: 10px; }

                        .store-badge {
                          flex: 1;
                          display: flex;
                          align-items: center;
                          gap: 11px;
                          padding: 13px 14px;
                          background: rgba(255,255,255,.04);
                          border: 1px solid var(--border);
                          border-radius: var(--r-sm);
                          text-decoration: none;
                          color: var(--text);
                          transition: background .15s, border-color .15s, transform .12s;
                          -webkit-tap-highlight-color: transparent;
                        }
                        .store-badge:active {
                          background: rgba(255,255,255,.08);
                          border-color: rgba(255,255,255,.2);
                          transform: scale(.97);
                        }

                        .badge-icon {
                          font-size: 24px;
                          line-height: 1;
                          flex-shrink: 0;
                        }
                        .badge-text { text-align: left; }
                        .badge-sub {
                          display: block;
                          font-size: 9px;
                          font-weight: 600;
                          letter-spacing: .5px;
                          text-transform: uppercase;
                          color: var(--muted);
                          margin-bottom: 2px;
                        }
                        .badge-name {
                          display: block;
                          font-size: 14px;
                          font-weight: 700;
                          letter-spacing: -.2px;
                        }

                        /* ── Footer ── */
                        .footer {
                          margin-top: 36px;
                          font-size: 12px;
                          color: var(--muted);
                          letter-spacing: .3px;
                        }
                      </style>
                    </head>
                    <body>

                      <div class="wordmark">
                        <span class="wordmark-dot"></span>
                        PushUp
                        <span class="wordmark-dot"></span>
                      </div>

                      <div class="card">

                        <div class="app-icon">💪</div>

                        <h1>You've been invited!</h1>
                        <p class="subtitle">
                          A friend wants to add you on PushUp —<br>
                          the app that lets you earn your screen time.
                        </p>

                        <div class="code-box">
                          <div class="code-label">Friend Code</div>
                          <div class="code-value">$formatted</div>
                        </div>

                        <a class="btn-primary" href="$appScheme">
                          <svg width="18" height="18" viewBox="0 0 24 24" fill="none"
                               stroke="currentColor" stroke-width="2.5"
                               stroke-linecap="round" stroke-linejoin="round">
                            <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/>
                            <circle cx="9" cy="7" r="4"/>
                            <line x1="19" y1="8" x2="19" y2="14"/>
                            <line x1="22" y1="11" x2="16" y2="11"/>
                          </svg>
                          Add Friend in PushUp
                        </a>

                        <div class="divider">Don't have the app yet?</div>

                        <div class="store-row">
                          <a class="store-badge" href="$appStoreUrl">
                            <span class="badge-icon">&#xF8FF;</span>
                            <span class="badge-text">
                              <span class="badge-sub">Download on the</span>
                              <span class="badge-name">App Store</span>
                            </span>
                          </a>
                          <a class="store-badge" href="$playStoreUrl">
                            <span class="badge-icon">&#9654;</span>
                            <span class="badge-text">
                              <span class="badge-sub">Get it on</span>
                              <span class="badge-name">Google Play</span>
                            </span>
                          </a>
                        </div>

                      </div>

                      <p class="footer">PushUp &middot; Earn your screen time</p>

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
