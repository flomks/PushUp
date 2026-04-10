package com.sinura.web

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
                "appID": "2986PL676H.com.flomks.sinura",
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
    title = "Sinura | Social Fitness",
    description = "Sinura verbindet Training, Freunde und spaeter sharebare Runs in einer klaren, dunklen und modernen Web-Erfahrung.",
) {
    """
    <main class="page-shell">
      <section class="topbar">
        <a class="brand" href="/">
          <span class="brand-mark"></span>
          <span>Sinura</span>
        </a>
        <div class="topbar-links">
          <a href="/friend/AB3X7K2M">Friend Code</a>
          <a href="/run/night-crew-berlin">Run Share</a>
        </div>
      </section>

      <section class="hero hero-home">
        <div class="hero-copy">
          <div class="eyebrow">Sinura Web</div>
          <h1>Training, Freunde und Runs in einer klaren dunklen Oberfläche.</h1>
          <p class="hero-text">
            Die Website ist jetzt eine echte Homebase fuer Sinura:
            hochwertiger Einstieg, sauberer Friend-Code-Flow und die Grundlage fuer spaeter oeffentliche Run-Seiten.
          </p>
          <div class="cta-row">
            <a class="btn btn-primary" href="/friend/AB3X7K2M">Freund hinzufuegen</a>
            <a class="btn btn-secondary" href="/run/night-crew-berlin">Run Preview ansehen</a>
          </div>
          <div class="hero-metrics">
            <div class="metric">
              <span class="metric-value">Live</span>
              <span class="metric-label">Friend-Code Landingpages</span>
            </div>
            <div class="metric">
              <span class="metric-value">Next</span>
              <span class="metric-label">Sharebare Runs und Recaps</span>
            </div>
            <div class="metric">
              <span class="metric-value">Ready</span>
              <span class="metric-label">Public Profiles und Challenges</span>
            </div>
          </div>
        </div>

        <div class="hero-stage">
          <div class="panel spotlight-panel">
            <div class="spotlight-grid">
              <div>
                <div class="panel-label">Product Surface</div>
                <h2>Weniger Landingpage, mehr Produkt.</h2>
              </div>
              <div class="status-stack">
                <div class="status-chip">Dark UI</div>
                <div class="status-chip">Deep Link Ready</div>
                <div class="status-chip">Run Sharing Ready</div>
              </div>
            </div>
            <div class="preview-shell">
              <div class="preview-header">
                <span class="preview-dot"></span>
                <span class="preview-dot"></span>
                <span class="preview-dot"></span>
              </div>
              <div class="preview-grid">
                <div class="preview-main">
                  <div class="preview-kicker">Session Layer</div>
                  <strong>Workout, Friend Graph und Running wachsen in dieselbe Experience.</strong>
                </div>
                <div class="preview-side">
                  <div class="preview-stat">
                    <span>Surface</span>
                    <strong>Web + App</strong>
                  </div>
                  <div class="preview-stat">
                    <span>Visuals</span>
                    <strong>Black / Lime / Steel</strong>
                  </div>
                  <div class="preview-stat">
                    <span>Phase</span>
                    <strong>Public Web Foundation</strong>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section class="section-grid">
        <article class="feature-card">
          <div class="card-index">01</div>
          <h3>Website als zentrale Flaeche</h3>
          <p>Die Domain ist nicht mehr nur Zwischenstation fuer Links, sondern eine saubere Produktoberflaeche.</p>
        </article>
        <article class="feature-card">
          <div class="card-index">02</div>
          <h3>Friend-Code-Flow mit mehr Qualitaet</h3>
          <p>Einladung, Deep Link und Store-Fallback fuehlen sich jetzt bewusst gestaltet und app-nah an.</p>
        </article>
        <article class="feature-card">
          <div class="card-index">03</div>
          <h3>Run-Share-Basis steht</h3>
          <p>Die Webstruktur ist vorbereitet fuer Distanz, Pace, Karten, Crew und spaetere oeffentliche Recaps.</p>
        </article>
      </section>

      <section class="vision-panel">
        <div>
          <div class="eyebrow">Roadmap</div>
          <h2>Die naechste Stufe ist nicht mehr Utility, sondern oeffentliche Fitness-Identity.</h2>
        </div>
        <div class="vision-list">
          <div class="vision-item">Run Recaps mit Karte, Pace und Story</div>
          <div class="vision-item">Crew-Seiten fuer gemeinsame Sessions</div>
          <div class="vision-item">Public Athlete Profiles mit XP und Streaks</div>
          <div class="vision-item">Challenge- und Referral-Landingpages</div>
        </div>
      </section>
    </main>
    """.trimIndent()
}

private fun renderFriendInvitePage(code: String): String {
    val normalizedCode = code.ifBlank { "PUSHUP00" }
    val formattedCode = normalizedCode.chunked(4).joinToString(" ")
    val appScheme = "sinura://friend-code/$normalizedCode"
    val appStoreUrl = "https://apps.apple.com/app/id0000000000"
    val playStoreUrl = "https://play.google.com/store/apps/details?id=com.flomks.sinura"

    return renderDocument(
        title = "Sinura | Friend Code $formattedCode",
        description = "Mit Sinura Freundescodes direkt verbinden und spaeter gemeinsam Runs, XP und Social Workouts teilen.",
    ) {
        """
        <main class="page-shell invite-shell">
          <section class="topbar">
            <a class="brand" href="/">
              <span class="brand-mark"></span>
              <span>Sinura</span>
            </a>
            <div class="topbar-links">
              <a href="/">Website</a>
              <a href="/run/night-crew-berlin">Run Share</a>
            </div>
          </section>

          <section class="hero hero-invite">
            <div class="invite-grid">
              <div class="invite-copy">
                <div class="eyebrow">Friend Invite</div>
                <h1>Jemand hat dir einen Sinura Friend Code geschickt.</h1>
                <p class="hero-text">
                  Oeffne den Code direkt in der App oder installiere Sinura und steig sauber in das soziale Setup ein.
                </p>

                <div class="invite-code-card">
                  <div class="invite-code-topline">Friend Code</div>
                  <div class="invite-code">$formattedCode</div>
                  <div class="invite-code-meta">Deep link ready &#183; mobile optimized &#183; invite flow</div>
                </div>

                <div class="cta-row">
                  <a class="btn btn-primary" href="$appScheme">In Sinura oeffnen</a>
                  <a class="btn btn-secondary" href="/">Zur Startseite</a>
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
                <div class="panel glass-panel">
                  <div class="panel-label">Invite Surface</div>
                  <h2>Klar, schnell, direkt auf den Punkt.</h2>
                  <p>
                    Der Friend-Code-Flow ist jetzt aufgeraeumt, dunkler und naeher an einer echten App-Experience.
                  </p>
                  <div class="bullet-panel">Starker Fokus auf den Code statt auf visuelle Ablenkung</div>
                  <div class="bullet-panel">Direkter Einstieg per Deep Link plus sauberer Store-Fallback</div>
                  <div class="bullet-panel">Visuelle Basis passend fuer spaetere Social- und Run-Shares</div>
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
        title = "Sinura | Run Share Preview",
        description = "Preview fuer oeffentliche Run-Share-Seiten in Sinura.",
    ) {
        """
        <main class="page-shell">
          <section class="topbar">
            <a class="brand" href="/">
              <span class="brand-mark"></span>
              <span>Sinura</span>
            </a>
            <div class="topbar-links">
              <a href="/">Website</a>
              <a href="/friend/AB3X7K2M">Friend Code</a>
            </div>
          </section>

          <section class="hero hero-run">
            <div class="hero-copy">
              <div class="eyebrow">Run Share</div>
              <div class="run-header-meta">
                <span class="run-status-pill">Public recap</span>
                <span class="run-status-copy">Sauber, mobil und sharebar.</span>
              </div>
              <h1>Aus einem geteilten Run wird ein klarer, moderner Recap.</h1>
              <p class="hero-text">
                Statt eines Platzhalters wirkt die Seite jetzt wie ein echtes Lauf-Highlight:
                starke Stat-Hierarchie, ruhige Karte, Splits, Crew-Kontext und eine sauberere
                Visual-Sprache fuer oeffentliche Session-Links.
              </p>
              <div class="run-kpis">
                <div class="run-kpi-card">
                  <span>Distance</span>
                  <strong>12.4 km</strong>
                </div>
                <div class="run-kpi-card">
                  <span>Moving Time</span>
                  <strong>59:31</strong>
                </div>
                <div class="run-kpi-card">
                  <span>Best Split</span>
                  <strong>4:32 /km</strong>
                </div>
              </div>
              <div class="panel run-story-card">
                <div class="panel-label">Session Snapshot</div>
                <h3>Night Crew Berlin</h3>
                <p>
                  Urban loop entlang Spree und Oberbaumbruecke, ruhiger Einstieg, schneller Mittelteil,
                  starker Finish-Abschnitt mit vier Leuten im gleichen Flow.
                </p>
              </div>
              <div class="cta-row">
                <a class="btn btn-primary" href="/">Zur Startseite</a>
                <a class="btn btn-secondary" href="/friend/AB3X7K2M">Friend Flow ansehen</a>
              </div>
            </div>

            <div class="panel share-board">
              <div class="share-board-top">
                <div class="share-chip">shareId: $safeId</div>
                <div class="share-availability">Live Recap</div>
              </div>
              <div class="share-stats share-stat-grid">
                <div><span>Distance</span><strong>12.4 km</strong></div>
                <div><span>Avg Pace</span><strong>4:48 /km</strong></div>
                <div><span>Elevation</span><strong>162 m</strong></div>
                <div><span>Crew</span><strong>4 runners</strong></div>
              </div>
              <div class="route-placeholder">
                <div class="map-pin map-pin-start">Start</div>
                <div class="map-pin map-pin-peak">Fast</div>
                <div class="map-pin map-pin-finish">Finish</div>
                <div class="route-line route-line-a"></div>
                <div class="route-line route-line-b"></div>
                <div class="route-line route-line-c"></div>
              </div>
              <div class="run-detail-grid">
                <div class="run-detail-card">
                  <div class="panel-label">Splits</div>
                  <div class="split-list">
                    <div class="split-row">
                      <span>KM 01</span>
                      <div class="split-bar"><i style="width: 72%"></i></div>
                      <strong>5:04</strong>
                    </div>
                    <div class="split-row">
                      <span>KM 05</span>
                      <div class="split-bar"><i style="width: 84%"></i></div>
                      <strong>4:42</strong>
                    </div>
                    <div class="split-row">
                      <span>KM 09</span>
                      <div class="split-bar"><i style="width: 91%"></i></div>
                      <strong>4:36</strong>
                    </div>
                  </div>
                </div>
                <div class="run-detail-card">
                  <div class="panel-label">Crew</div>
                  <div class="runner-stack">
                    <div class="runner-row">
                      <span class="runner-badge">LK</span>
                      <div>
                        <strong>Lena</strong>
                        <span>Lead pace</span>
                      </div>
                    </div>
                    <div class="runner-row">
                      <span class="runner-badge">MS</span>
                      <div>
                        <strong>Mika</strong>
                        <span>Negativ split</span>
                      </div>
                    </div>
                    <div class="runner-row">
                      <span class="runner-badge">+2</span>
                      <div>
                        <strong>Weitere Runner</strong>
                        <span>Konstant bis ins Ziel</span>
                      </div>
                    </div>
                  </div>
                </div>
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
          --bg: #050505;
          --bg-soft: #0b0b0b;
          --panel: rgba(18, 18, 18, 0.92);
          --panel-strong: rgba(12, 12, 12, 0.96);
          --panel-soft: rgba(255, 255, 255, 0.03);
          --line: rgba(255, 255, 255, 0.08);
          --line-strong: rgba(255, 255, 255, 0.14);
          --text: #f5f5f2;
          --muted: rgba(245, 245, 242, 0.70);
          --muted-soft: rgba(245, 245, 242, 0.46);
          --accent: #d7ff64;
          --accent-strong: #efffb4;
          --shadow: 0 30px 90px rgba(0, 0, 0, 0.45);
          --radius-xl: 30px;
          --radius-lg: 22px;
          --radius-md: 16px;
          --max: 1240px;
        }

        body {
          font-family: "Space Grotesk", "Avenir Next", "Segoe UI", sans-serif;
          color: var(--text);
          background:
            radial-gradient(circle at top right, rgba(215, 255, 100, 0.12), transparent 18%),
            radial-gradient(circle at bottom left, rgba(255, 255, 255, 0.05), transparent 24%),
            linear-gradient(180deg, #030303 0%, #080808 100%);
          background-attachment: fixed;
        }

        body::before {
          content: "";
          position: fixed;
          inset: 0;
          pointer-events: none;
          background:
            linear-gradient(180deg, rgba(255,255,255,0.02), transparent 24%),
            linear-gradient(90deg, rgba(255,255,255,0.02) 1px, transparent 1px),
            linear-gradient(rgba(255,255,255,0.02) 1px, transparent 1px);
          background-size: auto, 28px 28px, 28px 28px;
          mask-image: radial-gradient(circle at center, black 42%, transparent 100%);
          opacity: 0.38;
        }

        a { color: inherit; text-decoration: none; }
        code {
          font-family: "SF Mono", "Cascadia Code", Consolas, monospace;
          background: rgba(255,255,255,0.06);
          border: 1px solid rgba(255,255,255,0.1);
          padding: 0.15rem 0.4rem;
          border-radius: 999px;
        }

        .topbar {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 16px;
          margin-bottom: 18px;
          padding: 14px 18px;
          border: 1px solid var(--line);
          border-radius: 999px;
          background: rgba(14, 14, 14, 0.84);
          backdrop-filter: blur(14px);
          -webkit-backdrop-filter: blur(14px);
        }

        .brand {
          display: inline-flex;
          align-items: center;
          gap: 10px;
          font-weight: 700;
          letter-spacing: -0.03em;
        }

        .brand-mark {
          width: 12px;
          height: 12px;
          border-radius: 50%;
          background: var(--accent);
          box-shadow: 0 0 22px rgba(215, 255, 100, 0.45);
        }

        .topbar-links {
          display: flex;
          flex-wrap: wrap;
          gap: 14px;
          color: var(--muted);
          font-size: 0.95rem;
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
            linear-gradient(180deg, rgba(255,255,255,0.02), rgba(255,255,255,0)),
            linear-gradient(135deg, rgba(215,255,100,0.06), rgba(255,255,255,0));
          box-shadow: var(--shadow);
          backdrop-filter: blur(18px);
          -webkit-backdrop-filter: blur(18px);
        }

        .hero::after {
          content: "";
          position: absolute;
          inset: auto -10% -24% auto;
          width: 280px;
          height: 280px;
          background: radial-gradient(circle, rgba(215,255,100,0.12), transparent 72%);
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
        .panel-label,
        .preview-kicker,
        .invite-code-topline,
        .store-overline {
          color: var(--accent-strong);
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
          color: #0a0a07;
          background: linear-gradient(180deg, var(--accent) 0%, #bedf5f 100%);
          border-color: rgba(215,255,100,0.30);
        }

        .btn-secondary {
          background: rgba(255,255,255,0.03);
          color: var(--text);
        }

        .panel,
        .hero-metrics .metric,
        .feature-card,
        .vision-panel,
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

        .spotlight-panel,
        .glass-panel,
        .share-board {
          padding: 24px;
        }

        .spotlight-grid {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: 16px;
        }

        .status-stack {
          display: flex;
          flex-wrap: wrap;
          justify-content: flex-end;
          gap: 10px;
        }

        .status-chip {
          padding: 0.55rem 0.9rem;
          border-radius: 999px;
          border: 1px solid var(--line);
          color: var(--muted);
          background: rgba(255,255,255,0.03);
          font-size: 0.9rem;
        }

        .preview-shell {
          margin-top: 22px;
          border: 1px solid var(--line);
          border-radius: var(--radius-lg);
          overflow: hidden;
          background: linear-gradient(180deg, rgba(255,255,255,0.03), rgba(255,255,255,0.01));
        }

        .preview-header {
          display: flex;
          gap: 8px;
          padding: 14px 16px;
          border-bottom: 1px solid var(--line);
          background: rgba(255,255,255,0.02);
        }

        .preview-dot {
          width: 9px;
          height: 9px;
          border-radius: 50%;
          background: rgba(255,255,255,0.18);
        }

        .preview-grid {
          display: grid;
          grid-template-columns: 1.2fr 0.8fr;
          gap: 16px;
          padding: 18px;
        }

        .preview-main,
        .preview-stat {
          padding: 18px;
          border: 1px solid var(--line);
          border-radius: var(--radius-md);
          background: var(--panel-soft);
        }

        .preview-main strong,
        .store-card strong {
          display: block;
          margin-top: 10px;
          font-size: 1.02rem;
          line-height: 1.3;
        }

        .preview-side {
          display: grid;
          gap: 12px;
        }

        .preview-stat span {
          display: block;
          color: var(--muted-soft);
          font-size: 0.82rem;
          text-transform: uppercase;
          letter-spacing: 0.12em;
        }

        .preview-stat strong {
          display: block;
          margin-top: 8px;
          font-size: 1rem;
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
          background: linear-gradient(135deg, rgba(215,255,100,0.22), rgba(255,255,255,0.08));
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
          background: rgba(255,255,255,0.025);
        }

        .invite-code-card {
          padding: 22px;
          background:
            linear-gradient(180deg, rgba(215,255,100,0.08), rgba(255,255,255,0.02)),
            var(--panel);
        }

        .invite-code {
          margin: 14px 0 10px;
          font-family: "SF Mono", "Cascadia Code", Consolas, monospace;
          font-size: clamp(2rem, 8vw, 4rem);
          font-weight: 800;
          letter-spacing: 0.18em;
          line-height: 1;
          text-shadow: 0 0 24px rgba(215,255,100,0.12);
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
          background: rgba(255,255,255,0.025);
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

        .run-header-meta,
        .share-board-top,
        .runner-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
        }

        .run-status-pill,
        .share-availability {
          display: inline-flex;
          align-items: center;
          min-height: 34px;
          padding: 0 12px;
          border-radius: 999px;
          border: 1px solid rgba(215,255,100,0.22);
          background: rgba(215,255,100,0.10);
          color: var(--accent-strong);
          font-size: 0.82rem;
          font-weight: 700;
          letter-spacing: 0.06em;
          text-transform: uppercase;
        }

        .run-status-copy {
          color: var(--muted-soft);
          font-size: 0.94rem;
        }

        .run-kpis,
        .run-detail-grid,
        .split-list,
        .runner-stack {
          display: grid;
          gap: 12px;
        }

        .run-kpis {
          grid-template-columns: repeat(3, minmax(0, 1fr));
        }

        .run-kpi-card,
        .run-detail-card {
          padding: 18px;
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: var(--radius-md);
          background: rgba(255,255,255,0.025);
        }

        .run-kpi-card span,
        .runner-row span,
        .split-row span {
          display: block;
          color: var(--muted-soft);
          font-size: 0.82rem;
          letter-spacing: 0.08em;
          text-transform: uppercase;
        }

        .run-kpi-card strong {
          display: block;
          margin-top: 10px;
          font-size: 1.7rem;
          letter-spacing: -0.05em;
        }

        .run-story-card {
          display: grid;
          gap: 10px;
          padding: 22px;
        }

        .share-board-top {
          margin-bottom: 16px;
        }

        .share-stat-grid {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: 14px;
        }

        .share-stats > div {
          padding: 18px;
          border-radius: var(--radius-md);
          background: rgba(255,255,255,0.025);
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
            linear-gradient(135deg, rgba(7, 9, 18, 0.96), rgba(12, 15, 22, 0.82)),
            radial-gradient(circle at 30% 25%, rgba(215,255,100,0.10), transparent 28%),
            linear-gradient(180deg, rgba(255,255,255,0.04), rgba(255,255,255,0.01));
        }

        .route-placeholder::before {
          content: "";
          position: absolute;
          inset: 0;
          background:
            linear-gradient(90deg, rgba(255,255,255,0.04) 1px, transparent 1px),
            linear-gradient(rgba(255,255,255,0.04) 1px, transparent 1px);
          background-size: 56px 56px;
          opacity: 0.26;
        }

        .route-line {
          position: absolute;
          inset: auto;
          border-radius: 999px;
          border: 3px solid rgba(215,255,100,0.72);
          filter: drop-shadow(0 0 22px rgba(215,255,100,0.18));
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
          border-color: rgba(255,255,255,0.55);
        }

        .route-line-c {
          width: 120px;
          height: 120px;
          left: 168px;
          bottom: 24px;
          border-color: rgba(215,255,100,0.42);
        }

        .map-pin {
          position: absolute;
          z-index: 1;
          padding: 0.4rem 0.7rem;
          border-radius: 999px;
          border: 1px solid rgba(255,255,255,0.10);
          background: rgba(8,10,16,0.88);
          color: var(--text);
          font-size: 0.76rem;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          box-shadow: 0 12px 30px rgba(0,0,0,0.22);
        }

        .map-pin-start {
          top: 26px;
          left: 22px;
        }

        .map-pin-peak {
          top: 112px;
          right: 42px;
        }

        .map-pin-finish {
          bottom: 20px;
          left: 148px;
        }

        .run-detail-grid {
          grid-template-columns: repeat(2, minmax(0, 1fr));
          margin-top: 18px;
        }

        .split-row {
          display: grid;
          grid-template-columns: auto 1fr auto;
          align-items: center;
          gap: 12px;
        }

        .split-row strong,
        .runner-row strong {
          font-size: 1rem;
          letter-spacing: -0.02em;
        }

        .split-bar {
          height: 10px;
          border-radius: 999px;
          background: rgba(255,255,255,0.06);
          overflow: hidden;
        }

        .split-bar i {
          display: block;
          height: 100%;
          border-radius: inherit;
          background: linear-gradient(90deg, rgba(215,255,100,0.42), rgba(215,255,100,0.92));
          box-shadow: 0 0 18px rgba(215,255,100,0.18);
        }

        .runner-badge {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 42px;
          height: 42px;
          border-radius: 14px;
          border: 1px solid rgba(255,255,255,0.10);
          background: rgba(255,255,255,0.05);
          color: var(--text);
          font-size: 0.9rem;
          font-weight: 700;
          letter-spacing: -0.03em;
          text-transform: none;
        }

        .runner-row {
          justify-content: flex-start;
          padding: 10px 0;
        }

        .runner-row div span {
          margin-top: 4px;
          letter-spacing: normal;
          text-transform: none;
        }

        @media (max-width: 980px) {
          .hero-home,
          .hero-run,
          .invite-grid,
          .preview-grid,
          .vision-panel {
            grid-template-columns: 1fr;
          }

          .spotlight-grid {
            flex-direction: column;
          }

          .status-stack {
            justify-content: flex-start;
          }

          h1 {
            max-width: none;
            font-size: clamp(2.6rem, 12vw, 4.5rem);
          }

          .run-kpis,
          .share-stat-grid,
          .run-detail-grid {
            grid-template-columns: 1fr;
          }
        }

        @media (max-width: 640px) {
          .page-shell {
            width: min(calc(100% - 18px), var(--max));
            padding-top: 12px;
            padding-bottom: 28px;
          }

          .topbar {
            border-radius: 24px;
            padding: 14px;
          }

          .topbar-links {
            width: 100%;
            justify-content: space-between;
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

          .run-header-meta,
          .share-board-top,
          .split-row {
            grid-template-columns: 1fr;
            display: grid;
          }

          .run-status-copy {
            font-size: 0.88rem;
          }

          .runner-row {
            grid-template-columns: auto 1fr;
            display: grid;
            align-items: center;
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
