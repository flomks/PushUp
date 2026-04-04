package com.pushup.web

import io.ktor.http.ContentType
import io.ktor.server.response.respondText
import io.ktor.server.routing.Route
import io.ktor.server.routing.get

fun Route.publicWebRoutes() {
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

    get("/") {
        call.respondText(
            contentType = ContentType.Text.Html,
            text = renderHomePage(),
        )
    }

    get("/.well-known/apple-app-site-association") {
        call.respondText(aasa, ContentType.Application.Json)
    }

    get("/apple-app-site-association") {
        call.respondText(aasa, ContentType.Application.Json)
    }

    get("/friend/{code}") {
        val code = call.parameters["code"]
            ?.uppercase()
            ?.filter { it.isLetterOrDigit() }
            .orEmpty()

        call.response.headers.append("Cache-Control", "no-cache, no-store, must-revalidate")
        call.response.headers.append("Pragma", "no-cache")
        call.response.headers.append("Expires", "0")

        call.respondText(
            contentType = ContentType.Text.Html,
            text = renderFriendInvitePage(code = code),
        )
    }

    get("/run/{shareId}") {
        val shareId = call.parameters["shareId"]
            ?.filter { it.isLetterOrDigit() || it == '-' || it == '_' }
            .orEmpty()

        call.respondText(
            contentType = ContentType.Text.Html,
            text = renderRunSharePreviewPage(shareId = shareId),
        )
    }
}

private fun renderHomePage(): String = renderDocument(
    title = "PushUp | Train hard. Earn time back.",
    description = "PushUp verbindet Workouts, Freunde, Codes und spaeter oeffentliche Run-Share-Seiten in einer radikal modernen Web-Erfahrung.",
) {
    """
    <main class="page-shell">
      <section class="hero hero-home">
        <div class="hero-copy">
          <div class="eyebrow">PushUp Web Platform</div>
          <h1>Fitness, Social Graph und Shareable Runs auf einer Website, die nicht wie ein nachtraeglicher Anhang aussieht.</h1>
          <p class="hero-text">
            PushUp bekommt eine echte digitale Homebase: Friend-Code-Landingpages, markante Produktpraesenz,
            Public Share Pages fuer Runs und eine Web-Oberflaeche, die auf Wachstum vorbereitet ist.
          </p>
          <div class="cta-row">
            <a class="btn btn-primary" href="/friend/AB3X7K2M">Friend Code Experience</a>
            <a class="btn btn-secondary" href="/run/night-crew-berlin">Run Share Preview</a>
          </div>
          <div class="hero-metrics">
            <div class="metric">
              <span class="metric-value">01</span>
              <span class="metric-label">Unified public website</span>
            </div>
            <div class="metric">
              <span class="metric-value">02</span>
              <span class="metric-label">Friend-code landing flows</span>
            </div>
            <div class="metric">
              <span class="metric-value">03</span>
              <span class="metric-label">Run sharing foundation</span>
            </div>
          </div>
        </div>

        <div class="hero-stage">
          <div class="stage-card stage-card-main">
            <div class="stage-kicker">Live Identity</div>
            <h2>Ein Web-Layer, der sich wie Produkt anfuehlt, nicht wie Utility.</h2>
            <p>
              Klare Entry-Points fuer neue User, starke visuelle Sprache und eine Struktur, die spaeter mit echten
              Share-Daten, Leaderboards und Public Profiles erweitert werden kann.
            </p>
          </div>
          <div class="stage-card-grid">
            <article class="mini-panel">
              <span class="mini-label">Friend Codes</span>
              <strong>Deep Links, Store Fallbacks, saubere Brand-Praesenz</strong>
            </article>
            <article class="mini-panel">
              <span class="mini-label">Runs</span>
              <strong>Sharebare Pages fuer Distanz, Pace, Route, Crew und Storytelling</strong>
            </article>
            <article class="mini-panel">
              <span class="mini-label">Future Surface</span>
              <strong>Events, Public Profiles, Challenge Pages und Rankings</strong>
            </article>
          </div>
        </div>
      </section>

      <section class="section-grid">
        <article class="feature-card">
          <div class="card-index">01</div>
          <h3>Neue Startseite unter <code>/</code></h3>
          <p>
            Die Domain ist jetzt nicht mehr nur Ziel fuer Friend-Links, sondern eine vollwertige Produktseite mit klarer
            Navigation in die wichtigsten Social-Flows.
          </p>
        </article>
        <article class="feature-card">
          <div class="card-index">02</div>
          <h3>Friend-Code-Seite komplett neu gedacht</h3>
          <p>
            Der Invite-Flow wirkt hochwertiger, emotionaler und deutlich naeher an einer modernen Consumer Brand.
          </p>
        </article>
        <article class="feature-card">
          <div class="card-index">03</div>
          <h3>Run-Share-Route vorbereitet</h3>
          <p>
            Unter <code>/run/&lt;shareId&gt;</code> steht eine hochwertige Preview-Struktur bereit, die spaeter nur noch an echte Daten angebunden werden muss.
          </p>
        </article>
      </section>

      <section class="vision-panel">
        <div>
          <div class="eyebrow">What comes next</div>
          <h2>Die Architektur ist jetzt bereit fuer oeffentliche Trainingsmomente.</h2>
        </div>
        <div class="vision-list">
          <div class="vision-item">Sharebare Run Recaps mit Distanz, Pace, Hoehenmetern und Karten-Snippets</div>
          <div class="vision-item">Event Pages fuer Crew Runs inklusive Teilnehmern und Status</div>
          <div class="vision-item">Public Athlete Profiles mit XP, Streaks und Freundesnetzwerk</div>
          <div class="vision-item">Landingpages fuer Challenges, Invite-Kampagnen und Referral Loops</div>
        </div>
      </section>
    </main>
    """.trimIndent()
}

private fun renderFriendInvitePage(code: String): String {
    val normalizedCode = code.ifBlank { "PUSHUP00" }
    val formattedCode = normalizedCode.chunked(4).joinToString(" ")
    val appScheme = "pushup://friend-code/$normalizedCode"
    val appStoreUrl = "https://apps.apple.com/app/id0000000000"
    val playStoreUrl = "https://play.google.com/store/apps/details?id=com.flomks.pushup"

    return renderDocument(
        title = "PushUp | Friend Code $formattedCode",
        description = "Mit PushUp Freundescodes direkt verbinden und spaeter gemeinsam Runs, XP und Social Workouts teilen.",
    ) {
        """
        <main class="page-shell invite-shell">
          <section class="hero hero-invite">
            <div class="invite-grid">
              <div class="invite-copy">
                <div class="eyebrow">PushUp Friend Link</div>
                <h1>Jemand will dich in seine PushUp-Crew holen.</h1>
                <p class="hero-text">
                  Verbinde dich per Friend Code, starte gemeinsame Social Features und bereite die Basis fuer
                  geteilte Runs, Live Sessions und spaetere Public Highlights.
                </p>

                <div class="invite-code-card">
                  <div class="invite-code-topline">Friend Code</div>
                  <div class="invite-code">$formattedCode</div>
                  <div class="invite-code-meta">Deep link ready &#183; mobile optimized &#183; social onboarding</div>
                </div>

                <div class="cta-row">
                  <a class="btn btn-primary" href="$appScheme">In PushUp oeffnen</a>
                  <a class="btn btn-secondary" href="/">Zur Website</a>
                </div>

                <div class="store-strip">
                  <a class="store-card" href="$appStoreUrl">
                    <span class="store-overline">Download on the</span>
                    <strong>App Store</strong>
                  </a>
                  <a class="store-card" href="$playStoreUrl">
                    <span class="store-overline">Get it on</span>
                    <strong>Google Play</strong>
                  </a>
                </div>
              </div>

              <div class="invite-stage">
                <div class="glass-panel">
                  <div class="stack-label">Why this matters</div>
                  <h2>Vom Invite direkt in ein spaeteres Social Fitness Netzwerk.</h2>
                  <p>
                    Der Friend-Code-Flow fuehlt sich jetzt wie ein echter Einstiegspunkt ins Produkt an,
                    nicht wie eine nackte Zwischen-Seite.
                  </p>
                  <div class="bullet-panel">Modernes Brand-Layout mit starkem Hero, klaren CTA-Pfaden und visuellem Fokus auf den Code</div>
                  <div class="bullet-panel">Optimiert fuer Mobile-Deep-Links und App-Store-Fallbacks</div>
                  <div class="bullet-panel">Passend zur naechsten Phase: sharebare Runs, Crew Events, Public Activity Pages</div>
                </div>
              </div>
            </div>
          </section>
        </main>
        """.trimIndent()
    }
}

private fun renderRunSharePreviewPage(shareId: String): String {
    val safeId = shareId.ifBlank { "crew-run-preview" }.escapeHtml()

    return renderDocument(
        title = "PushUp | Run Share Preview",
        description = "Preview fuer oeffentliche Run-Share-Seiten in PushUp.",
    ) {
        """
        <main class="page-shell">
          <section class="hero hero-run">
            <div class="hero-copy">
              <div class="eyebrow">Public Run Share</div>
              <h1>Run pages koennen jetzt als eigenstaendige Erlebnis-Seiten gedacht werden.</h1>
              <p class="hero-text">
                Diese Route ist die vorbereitete Web-Flaeche fuer geteilte Runs. Heute als hochwertige Preview,
                spaeter mit echten Daten aus Jogging Sessions, Playback Entries und Social Running.
              </p>
              <div class="cta-row">
                <a class="btn btn-primary" href="/">Zur Startseite</a>
                <a class="btn btn-secondary" href="/friend/AB3X7K2M">Friend Flow ansehen</a>
              </div>
            </div>

            <div class="share-board">
              <div class="share-chip">shareId: $safeId</div>
              <div class="share-stats">
                <div><span>Distance</span><strong>12.4 km</strong></div>
                <div><span>Avg Pace</span><strong>4:48 /km</strong></div>
                <div><span>Elevation</span><strong>162 m</strong></div>
                <div><span>Crew</span><strong>4 runners</strong></div>
              </div>
              <div class="route-placeholder">
                <div class="route-line route-line-a"></div>
                <div class="route-line route-line-b"></div>
                <div class="route-line route-line-c"></div>
              </div>
            </div>
          </section>
        </main>
        """.trimIndent()
    }
}

private fun renderDocument(
    title: String,
    description: String,
    body: () -> String,
): String = """
    <!DOCTYPE html>
    <html lang="de">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
      <meta name="theme-color" content="#050816">
      <meta name="description" content="${description.escapeHtml()}">
      <title>${title.escapeHtml()}</title>
      <style>
        *, *::before, *::after { box-sizing: border-box; }
        html { color-scheme: dark; }
        html, body { margin: 0; min-height: 100%; }

        :root {
          --bg: #050816;
          --bg-soft: #0c1330;
          --panel: rgba(8, 16, 40, 0.66);
          --panel-strong: rgba(10, 20, 48, 0.88);
          --line: rgba(255, 255, 255, 0.11);
          --text: #f4f7ff;
          --muted: rgba(226, 232, 255, 0.72);
          --muted-soft: rgba(226, 232, 255, 0.48);
          --accent: #67e8f9;
          --accent-2: #60a5fa;
          --accent-3: #f97316;
          --shadow: 0 32px 120px rgba(0, 0, 0, 0.42);
          --radius-xl: 32px;
          --radius-lg: 24px;
          --radius-md: 18px;
          --max: 1240px;
        }

        body {
          font-family: "Space Grotesk", "Avenir Next", "Segoe UI", sans-serif;
          color: var(--text);
          background:
            radial-gradient(circle at top left, rgba(103, 232, 249, 0.16), transparent 28%),
            radial-gradient(circle at 85% 18%, rgba(249, 115, 22, 0.14), transparent 24%),
            radial-gradient(circle at 50% 100%, rgba(96, 165, 250, 0.20), transparent 34%),
            linear-gradient(160deg, #030611 0%, #071127 42%, #050816 100%);
          background-attachment: fixed;
        }

        body::before {
          content: "";
          position: fixed;
          inset: 0;
          pointer-events: none;
          background-image:
            linear-gradient(rgba(255,255,255,0.03) 1px, transparent 1px),
            linear-gradient(90deg, rgba(255,255,255,0.03) 1px, transparent 1px);
          background-size: 36px 36px;
          mask-image: radial-gradient(circle at center, black 45%, transparent 100%);
          opacity: 0.32;
        }

        a { color: inherit; text-decoration: none; }
        code {
          font-family: "SF Mono", "Cascadia Code", Consolas, monospace;
          background: rgba(255,255,255,0.06);
          border: 1px solid rgba(255,255,255,0.1);
          padding: 0.15rem 0.4rem;
          border-radius: 999px;
        }

        .page-shell {
          width: min(calc(100% - 32px), var(--max));
          margin: 0 auto;
          padding: 32px 0 64px;
        }

        .hero {
          position: relative;
          overflow: hidden;
          border: 1px solid var(--line);
          border-radius: var(--radius-xl);
          background:
            linear-gradient(135deg, rgba(255,255,255,0.08), rgba(255,255,255,0.02)),
            linear-gradient(145deg, rgba(96, 165, 250, 0.16), rgba(0, 0, 0, 0));
          box-shadow: var(--shadow);
          backdrop-filter: blur(18px);
          -webkit-backdrop-filter: blur(18px);
        }

        .hero::after {
          content: "";
          position: absolute;
          inset: auto -12% -28% auto;
          width: 320px;
          height: 320px;
          background: radial-gradient(circle, rgba(103,232,249,0.18), transparent 70%);
          filter: blur(8px);
        }

        .hero-home,
        .hero-run {
          display: grid;
          grid-template-columns: 1.15fr 0.85fr;
          gap: 28px;
          padding: 36px;
        }

        .hero-invite {
          padding: 24px;
        }

        .invite-grid {
          display: grid;
          grid-template-columns: 1.1fr 0.9fr;
          gap: 22px;
        }

        .hero-copy,
        .invite-copy {
          display: flex;
          flex-direction: column;
          gap: 20px;
        }

        .eyebrow,
        .stack-label,
        .stage-kicker,
        .mini-label,
        .invite-code-topline,
        .store-overline {
          color: var(--accent);
          font-size: 0.78rem;
          font-weight: 700;
          letter-spacing: 0.14em;
          text-transform: uppercase;
        }

        h1 {
          margin: 0;
          font-size: clamp(2.9rem, 7vw, 5.8rem);
          line-height: 0.95;
          letter-spacing: -0.05em;
          max-width: 12ch;
        }

        h2, h3, p { margin: 0; }

        h2 {
          font-size: clamp(1.5rem, 3vw, 2.3rem);
          line-height: 1.05;
          letter-spacing: -0.04em;
        }

        h3 {
          font-size: 1.2rem;
          line-height: 1.1;
          letter-spacing: -0.02em;
        }

        .hero-text,
        .feature-card p,
        .vision-item,
        .stage-card p,
        .glass-panel p,
        .bullet-panel,
        .share-chip,
        .share-stats span {
          color: var(--muted);
          font-size: 1rem;
          line-height: 1.6;
        }

        .cta-row,
        .store-strip,
        .hero-metrics,
        .section-grid,
        .stage-card-grid,
        .vision-list,
        .share-stats {
          display: flex;
          flex-wrap: wrap;
          gap: 14px;
        }

        .btn {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          min-height: 54px;
          padding: 0 22px;
          border-radius: 999px;
          border: 1px solid var(--line);
          font-weight: 700;
          letter-spacing: -0.02em;
          transition: transform 160ms ease, border-color 160ms ease, background 160ms ease;
        }

        .btn:hover {
          transform: translateY(-1px);
          border-color: rgba(255,255,255,0.22);
        }

        .btn-primary {
          color: #04101f;
          background: linear-gradient(135deg, var(--accent) 0%, #93c5fd 50%, #f0abfc 100%);
        }

        .btn-secondary {
          background: rgba(255,255,255,0.05);
          color: var(--text);
        }

        .hero-metrics .metric,
        .mini-panel,
        .feature-card,
        .vision-panel,
        .stage-card,
        .glass-panel,
        .invite-code-card,
        .store-card,
        .share-board {
          border: 1px solid var(--line);
          background: var(--panel);
          border-radius: var(--radius-lg);
          backdrop-filter: blur(12px);
          -webkit-backdrop-filter: blur(12px);
        }

        .metric {
          min-width: 150px;
          padding: 18px 18px 16px;
        }

        .metric-value {
          display: block;
          margin-bottom: 8px;
          font-size: 1.8rem;
          font-weight: 800;
          letter-spacing: -0.05em;
        }

        .metric-label {
          color: var(--muted-soft);
          font-size: 0.95rem;
          line-height: 1.35;
        }

        .stage-card-main,
        .glass-panel,
        .share-board {
          padding: 24px;
        }

        .stage-card-grid {
          margin-top: 14px;
        }

        .mini-panel {
          flex: 1 1 180px;
          padding: 18px;
        }

        .mini-panel strong,
        .store-card strong {
          display: block;
          margin-top: 10px;
          font-size: 1.02rem;
          line-height: 1.3;
        }

        .section-grid {
          margin-top: 22px;
        }

        .feature-card {
          flex: 1 1 280px;
          padding: 24px;
        }

        .card-index {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 42px;
          height: 42px;
          margin-bottom: 18px;
          border-radius: 50%;
          background: linear-gradient(135deg, rgba(103,232,249,0.18), rgba(249,115,22,0.18));
          color: var(--text);
          font-weight: 800;
        }

        .vision-panel {
          display: grid;
          grid-template-columns: 0.95fr 1.05fr;
          gap: 24px;
          margin-top: 22px;
          padding: 28px;
          background: var(--panel-strong);
        }

        .vision-list {
          align-content: flex-start;
        }

        .vision-item {
          flex: 1 1 220px;
          padding: 16px 18px;
          border: 1px solid var(--line);
          border-radius: var(--radius-md);
          background: rgba(255,255,255,0.03);
        }

        .invite-code-card {
          padding: 22px;
          background:
            linear-gradient(180deg, rgba(96,165,250,0.12), rgba(255,255,255,0.02)),
            var(--panel);
        }

        .invite-code {
          margin: 14px 0 10px;
          font-family: "SF Mono", "Cascadia Code", Consolas, monospace;
          font-size: clamp(2rem, 8vw, 4rem);
          font-weight: 800;
          letter-spacing: 0.18em;
          line-height: 1;
          text-shadow: 0 0 32px rgba(103,232,249,0.24);
        }

        .invite-code-meta {
          color: var(--muted-soft);
          font-size: 0.92rem;
        }

        .store-card {
          flex: 1 1 180px;
          padding: 18px;
        }

        .bullet-panel {
          margin-top: 14px;
          padding: 14px 16px;
          border-radius: var(--radius-md);
          background: rgba(255,255,255,0.03);
          border: 1px solid rgba(255,255,255,0.07);
        }

        .share-chip {
          display: inline-flex;
          width: fit-content;
          padding: 0.55rem 0.85rem;
          border-radius: 999px;
          border: 1px solid rgba(255,255,255,0.10);
          background: rgba(255,255,255,0.04);
        }

        .share-stats > div {
          flex: 1 1 160px;
          padding: 18px;
          border-radius: var(--radius-md);
          background: rgba(255,255,255,0.03);
          border: 1px solid rgba(255,255,255,0.08);
        }

        .share-stats strong {
          display: block;
          margin-top: 10px;
          font-size: 1.5rem;
          letter-spacing: -0.04em;
        }

        .route-placeholder {
          position: relative;
          min-height: 280px;
          margin-top: 18px;
          overflow: hidden;
          border-radius: var(--radius-lg);
          border: 1px solid rgba(255,255,255,0.08);
          background:
            radial-gradient(circle at 30% 25%, rgba(103,232,249,0.10), transparent 28%),
            linear-gradient(180deg, rgba(255,255,255,0.04), rgba(255,255,255,0.01));
        }

        .route-line {
          position: absolute;
          inset: auto;
          border-radius: 999px;
          border: 3px solid rgba(103,232,249,0.7);
          filter: drop-shadow(0 0 24px rgba(103,232,249,0.24));
        }

        .route-line-a {
          width: 180px;
          height: 180px;
          top: 26px;
          left: 40px;
          transform: rotate(18deg);
        }

        .route-line-b {
          width: 220px;
          height: 120px;
          right: 34px;
          top: 84px;
          border-color: rgba(249,115,22,0.7);
        }

        .route-line-c {
          width: 120px;
          height: 120px;
          left: 168px;
          bottom: 24px;
          border-color: rgba(96,165,250,0.9);
        }

        @media (max-width: 980px) {
          .hero-home,
          .hero-run,
          .invite-grid,
          .vision-panel {
            grid-template-columns: 1fr;
          }

          h1 {
            max-width: none;
            font-size: clamp(2.6rem, 12vw, 4.5rem);
          }
        }

        @media (max-width: 640px) {
          .page-shell {
            width: min(calc(100% - 18px), var(--max));
            padding-top: 12px;
            padding-bottom: 28px;
          }

          .hero-home,
          .hero-run,
          .hero-invite {
            padding: 18px;
          }

          .invite-code {
            letter-spacing: 0.08em;
          }

          .btn,
          .store-card {
            width: 100%;
          }
        }
      </style>
    </head>
    <body>
      ${body()}
    </body>
    </html>
""".trimIndent()

private fun String.escapeHtml(): String = buildString(length) {
    for (char in this@escapeHtml) {
        when (char) {
            '&' -> append("&amp;")
            '<' -> append("&lt;")
            '>' -> append("&gt;")
            '"' -> append("&quot;")
            '\'' -> append("&#39;")
            else -> append(char)
        }
    }
}
