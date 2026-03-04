# PushUp Backend -- Deployment-Anleitung (Railway)

Diese Anleitung beschreibt Schritt fuer Schritt, wie du das Ktor-Backend auf
**Railway** deployst. Railway ist die empfohlene Plattform: einfaches Setup,
gutes Free-Tier (500 Stunden/Monat), automatische HTTPS-URL, integriertes
Logging und GitHub-Integration fuer Auto-Deploy.

---

## Inhaltsverzeichnis

1. [Voraussetzungen](#1-voraussetzungen)
2. [Railway-Projekt erstellen](#2-railway-projekt-erstellen)
3. [GitHub-Repository verbinden](#3-github-repository-verbinden)
4. [Umgebungsvariablen konfigurieren](#4-umgebungsvariablen-konfigurieren)
5. [Ersten Deploy ausloesen](#5-ersten-deploy-ausloesen)
6. [Public URL konfigurieren](#6-public-url-konfigurieren)
7. [Health-Check verifizieren](#7-health-check-verifizieren)
8. [Auto-Deploy bei Push auf main](#8-auto-deploy-bei-push-auf-main)
9. [Logging und Monitoring](#9-logging-und-monitoring)
10. [Lokaler Test vor dem Deploy](#10-lokaler-test-vor-dem-deploy)
11. [Troubleshooting](#11-troubleshooting)
12. [Alternative Plattformen](#12-alternative-plattformen)

---

## 1. Voraussetzungen

Bevor du anfaengst, stelle sicher dass du folgendes hast:

| Was | Wo besorgen |
|-----|-------------|
| Railway-Account | https://railway.app (kostenlos, GitHub-Login empfohlen) |
| GitHub-Repository | Dieses Repo muss auf GitHub liegen (bereits erledigt) |
| Supabase-Projekt | Muss bereits existieren (siehe `backend/README.md`) |
| Supabase JWT Secret | Supabase Dashboard > Settings > API > JWT Settings |
| Supabase Database URL | Supabase Dashboard > Settings > Database > Connection string (JDBC) |

---

## 2. Railway-Projekt erstellen

### Schritt 2.1 -- Einloggen

1. Gehe zu **https://railway.app**.
2. Klicke **Login** und waehle **Login with GitHub**.
3. Autorisiere Railway den Zugriff auf dein GitHub-Konto.

### Schritt 2.2 -- Neues Projekt anlegen

1. Klicke im Railway-Dashboard auf **New Project**.
2. Waehle **Deploy from GitHub repo**.
3. Falls Railway noch keinen Zugriff auf dein Repository hat:
   - Klicke **Configure GitHub App**.
   - Waehle dein GitHub-Konto.
   - Waehle **Only select repositories** und waehle `PushUp` (oder wie dein Repo heisst).
   - Klicke **Install & Authorize**.
4. Waehle das Repository `PushUp` aus der Liste.
5. Railway erkennt automatisch das `railway.toml` im Root und konfiguriert den Build.

### Schritt 2.3 -- Service benennen

1. Nach dem Erstellen siehst du einen Service-Block im Railway-Dashboard.
2. Klicke auf den Service-Block.
3. Klicke oben auf den Service-Namen (z.B. "PushUp") und aendere ihn zu:
   ```
   pushup-backend
   ```
4. Klicke Enter zum Speichern.

---

## 3. GitHub-Repository verbinden

Railway hat das Repository bereits in Schritt 2 verbunden. Stelle sicher, dass
der richtige Branch fuer Auto-Deploy konfiguriert ist:

1. Klicke im Railway-Dashboard auf deinen Service `pushup-backend`.
2. Gehe zum Tab **Settings**.
3. Scrolle zu **Source**.
4. Stelle sicher, dass **Branch** auf `main` gesetzt ist.
5. **Watch Paths** (optional): Trage ein `backend/**` damit Railway nur deployed
   wenn sich Backend-Dateien aendern (spart Build-Minuten).

---

## 4. Umgebungsvariablen konfigurieren

Dies ist der wichtigste Schritt. Ohne diese Variablen startet der Server nicht
korrekt in Production-Mode.

1. Klicke im Railway-Dashboard auf deinen Service `pushup-backend`.
2. Gehe zum Tab **Variables**.
3. Klicke **New Variable** und trage folgende Variablen ein:

### Pflicht-Variablen

| Variable | Wert | Wo finden |
|----------|------|-----------|
| `KTOR_ENV` | `production` | Fester Wert |
| `SUPABASE_JWT_SECRET` | `dein-jwt-secret` | Supabase > Settings > API > JWT Settings > JWT Secret |
| `JWT_ISSUER` | `https://<ref>.supabase.co/auth/v1` | Ersetze `<ref>` mit deiner Supabase-Projekt-Referenz |
| `DATABASE_URL` | `jdbc:postgresql://db.<ref>.supabase.co:5432/postgres?user=postgres&password=<pw>&sslmode=require` | Supabase > Settings > Database > Connection string > JDBC |

### Optionale Variablen

| Variable | Wert | Beschreibung |
|----------|------|--------------|
| `PORT` | `8080` | Railway setzt $PORT automatisch -- nur setzen wenn du einen anderen Port willst |
| `HOST` | `0.0.0.0` | Standardwert, muss normalerweise nicht gesetzt werden |
| `CORS_ALLOWED_HOSTS` | `deine-app.railway.app` | Komma-getrennte Liste erlaubter CORS-Hosts (ohne https://) |
| `LOG_LEVEL` | `INFO` | Logback Root-Log-Level: DEBUG, INFO, WARN, ERROR |
| `APP_LOG_LEVEL` | `INFO` | Log-Level fuer com.pushup.* Klassen |

### Wo du die Supabase-Werte findest

**JWT Secret:**
1. Oeffne dein Supabase-Projekt unter https://supabase.com/dashboard.
2. Klicke links auf **Settings** (Zahnrad-Icon).
3. Klicke auf **API**.
4. Scrolle zu **JWT Settings**.
5. Kopiere den Wert unter **JWT Secret**.

**JWT Issuer:**
- Format: `https://<dein-projekt-ref>.supabase.co/auth/v1`
- Deine Projekt-Referenz findest du in der URL deines Supabase-Projekts:
  `https://supabase.com/dashboard/project/<DEIN-REF>`

**Database URL (JDBC Format):**
1. Gehe zu **Settings > Database**.
2. Scrolle zu **Connection string**.
3. Klicke auf den Tab **JDBC**.
4. Kopiere den String -- er sieht so aus:
   ```
   jdbc:postgresql://db.<ref>.supabase.co:5432/postgres?user=postgres&password=<dein-passwort>&sslmode=require
   ```
5. Ersetze `[YOUR-PASSWORD]` mit dem Datenbankpasswort das du beim Erstellen des Projekts gesetzt hast.

---

## 5. Ersten Deploy ausloesen

Nach dem Setzen der Umgebungsvariablen:

1. Gehe zum Tab **Deployments** deines Services.
2. Klicke **Deploy Now** (oder pushe einen Commit auf `main`).
3. Railway baut jetzt das Docker-Image:
   - Gradle laedt Dependencies herunter (~2-3 Minuten beim ersten Mal)
   - Gradle baut den Fat-JAR (`./gradlew :backend:buildFatJar`)
   - Das Runtime-Image wird erstellt (eclipse-temurin:21-jre-alpine)
4. Nach dem Build startet Railway den Container.
5. Du siehst die Build-Logs in Echtzeit im Railway-Dashboard.

**Erwartete Build-Zeit:** 4-8 Minuten beim ersten Deploy (Gradle-Cache wird aufgebaut).
Folge-Deploys: 2-4 Minuten (Gradle-Cache ist warm).

**Erwartete Logs beim Start:**
```
INFO  Application - Responding at http://0.0.0.0:8080
INFO  Application - Initialising database connection pool ...
INFO  Application - Database connection pool ready (pool size: 10)
```

---

## 6. Public URL konfigurieren

Railway generiert automatisch eine URL fuer deinen Service. Du kannst auch eine
eigene Domain konfigurieren.

### Automatische Railway-URL aktivieren

1. Klicke auf deinen Service `pushup-backend`.
2. Gehe zum Tab **Settings**.
3. Scrolle zu **Networking**.
4. Klicke **Generate Domain**.
5. Railway generiert eine URL wie:
   ```
   https://pushup-backend-production-xxxx.up.railway.app
   ```

### Eigene Subdomain (optional)

1. Klicke unter **Networking** auf **Custom Domain**.
2. Trage deine Domain ein, z.B. `api.pushupapp.com`.
3. Folge den Anweisungen um den DNS-Eintrag bei deinem Domain-Anbieter zu setzen.

### URL in den Umgebungsvariablen eintragen

Sobald du die URL hast, trage sie als CORS-Host ein:

1. Gehe zu **Variables**.
2. Setze `CORS_ALLOWED_HOSTS` auf deine Railway-URL (ohne `https://`):
   ```
   pushup-backend-production-xxxx.up.railway.app
   ```
3. Railway deployed automatisch neu mit der neuen Variable.

---

## 7. Health-Check verifizieren

Sobald der Deploy abgeschlossen ist, teste den Health-Check-Endpunkt:

```bash
curl https://pushup-backend-production-xxxx.up.railway.app/health
```

**Erwartete Antwort:**
```json
{"status":"ok"}
```

**HTTP Status:** `200 OK`

Falls du eine andere Antwort bekommst, pruefe die Logs im Railway-Dashboard
(Tab **Logs** deines Services).

---

## 8. Auto-Deploy bei Push auf main

Railway deployed automatisch bei jedem Push auf `main`, sobald das Repository
verbunden ist (Schritt 3). Zusaetzlich gibt es einen GitHub Actions Workflow
(`.github/workflows/deploy.yml`) der den Deploy explizit ausloest.

### GitHub Actions Workflow einrichten (fuer explizite Deploy-Kontrolle)

Der Workflow in `.github/workflows/deploy.yml` benoetigt ein Railway-Token als
GitHub Secret.

**Railway-Token erstellen:**
1. Gehe zu https://railway.app/account/tokens.
2. Klicke **Create Token**.
3. Gib dem Token einen Namen, z.B. `github-actions-deploy`.
4. Kopiere den Token (er wird nur einmal angezeigt).

**Token als GitHub Secret hinterlegen:**
1. Gehe zu deinem GitHub-Repository.
2. Klicke auf **Settings** (Repository-Einstellungen, nicht Account-Einstellungen).
3. Klicke links auf **Secrets and variables > Actions**.
4. Klicke **New repository secret**.
5. Name: `RAILWAY_TOKEN`
6. Value: der kopierte Railway-Token
7. Klicke **Add secret**.

**Workflow testen:**
1. Pushe einen Commit auf `main` der eine Datei in `backend/` aendert.
2. Gehe zu **Actions** in deinem GitHub-Repository.
3. Du siehst den Workflow **Deploy to Railway** laufen.
4. Nach Abschluss siehst du im Railway-Dashboard einen neuen Deploy.

### Nur Railway-Integration (ohne GitHub Actions)

Wenn du den GitHub Actions Workflow nicht nutzen moechtest, kannst du ihn
ignorieren -- Railway deployed trotzdem automatisch bei jedem Push auf `main`
ueber die direkte GitHub-Integration (Schritt 3).

---

## 9. Logging und Monitoring

### Logs im Railway-Dashboard

1. Klicke auf deinen Service `pushup-backend`.
2. Gehe zum Tab **Logs**.
3. Du siehst alle stdout/stderr Ausgaben des Containers in Echtzeit.
4. Nutze die Suchfunktion um nach bestimmten Log-Eintraegen zu filtern.

### Log-Level anpassen

Setze die Umgebungsvariable `LOG_LEVEL` auf einen der folgenden Werte:
- `DEBUG` -- sehr ausfuehrlich (nur fuer Debugging)
- `INFO` -- Standard (empfohlen fuer Production)
- `WARN` -- nur Warnungen und Fehler
- `ERROR` -- nur Fehler

Fuer mehr Details aus dem Backend-Code:
```
APP_LOG_LEVEL=DEBUG
```

### Metriken

Railway zeigt im Tab **Metrics** folgende Werte:
- CPU-Auslastung
- RAM-Verbrauch
- Netzwerk-Traffic (eingehend/ausgehend)

### Alerts (optional)

1. Gehe zu deinem Service > **Settings** > **Alerts**.
2. Konfiguriere Benachrichtigungen fuer:
   - Deploy-Fehler
   - Service-Absturz
   - Hohe CPU/RAM-Auslastung

---

## 10. Lokaler Test vor dem Deploy

Bevor du deployst, kannst du das Docker-Image lokal testen:

### Voraussetzungen

- Docker Desktop installiert und gestartet

### Image bauen

```bash
# Vom Repository-Root aus
docker build -f backend/Dockerfile -t pushup-backend:local .
```

### Container starten

```bash
docker run --rm \
  -p 8080:8080 \
  -e KTOR_ENV=development \
  -e PORT=8080 \
  pushup-backend:local
```

Fuer einen vollstaendigen Test mit Datenbank:

```bash
docker run --rm \
  -p 8080:8080 \
  -e KTOR_ENV=production \
  -e PORT=8080 \
  -e SUPABASE_JWT_SECRET=dein-jwt-secret \
  -e JWT_ISSUER=https://dein-ref.supabase.co/auth/v1 \
  -e DATABASE_URL="jdbc:postgresql://db.dein-ref.supabase.co:5432/postgres?user=postgres&password=dein-pw&sslmode=require" \
  pushup-backend:local
```

### Health-Check testen

```bash
curl http://localhost:8080/health
# Erwartete Antwort: {"status":"ok"}
```

---

## 11. Troubleshooting

### "Build failed" im Railway-Dashboard

**Symptom:** Der Build schlaegt fehl, Logs zeigen Gradle-Fehler.

**Loesung:**
1. Pruefe die Build-Logs im Railway-Dashboard (Tab **Deployments** > klicke auf den fehlgeschlagenen Deploy).
2. Haeufige Ursachen:
   - Gradle-Version inkompatibel: Pruefe `gradle/wrapper/gradle-wrapper.properties`
   - Speicher-Limit: Railway Free-Tier hat 512 MB RAM fuer Builds. Der Gradle-Build
     benoetigt ~1 GB. Upgrade auf Hobby-Plan oder nutze den GitHub Actions Workflow
     der das Image baut und zu Railway pusht.

### "Container failed to start"

**Symptom:** Build erfolgreich, aber der Container startet nicht.

**Loesung:**
1. Pruefe die Logs im Tab **Logs**.
2. Haeufige Ursachen:
   - `DATABASE_URL` fehlt oder ist falsch: Pruefe den JDBC-String auf Tippfehler.
   - `SUPABASE_JWT_SECRET` fehlt: Muss in Production gesetzt sein.
   - Port-Konflikt: Railway setzt `$PORT` automatisch. Stelle sicher dass `PORT`
     nicht auf einen anderen Wert gesetzt ist.

### "Health check failed"

**Symptom:** Container startet, aber Railway markiert ihn als unhealthy.

**Loesung:**
1. Pruefe ob `/health` erreichbar ist: `curl https://deine-url.railway.app/health`
2. Pruefe die Logs auf Fehler beim Datenbankverbindungsaufbau.
3. Stelle sicher dass `KTOR_ENV=production` gesetzt ist.

### "401 Unauthorized" bei API-Aufrufen

**Symptom:** Alle geschuetzten Endpunkte geben 401 zurueck.

**Loesung:**
1. Pruefe ob `SUPABASE_JWT_SECRET` korrekt gesetzt ist (kein fuehrendes/nachfolgendes Leerzeichen).
2. Pruefe ob `JWT_ISSUER` korrekt ist (Format: `https://<ref>.supabase.co/auth/v1`).
3. Stelle sicher dass der JWT-Token im `Authorization: Bearer <token>` Header mitgeschickt wird.

### "Connection refused" zur Datenbank

**Symptom:** Logs zeigen `Connection refused` oder `timeout` beim Datenbankverbindungsaufbau.

**Loesung:**
1. Pruefe ob `DATABASE_URL` den korrekten Supabase-Host enthaelt.
2. Stelle sicher dass `sslmode=require` im JDBC-String enthalten ist.
3. Pruefe ob das Datenbankpasswort korrekt ist (keine URL-Encoding-Probleme bei Sonderzeichen).
   Falls das Passwort Sonderzeichen enthaelt, URL-encode sie:
   - `@` -> `%40`
   - `#` -> `%23`
   - `$` -> `%24`

### Langsame Build-Zeiten

**Symptom:** Jeder Build dauert 8+ Minuten.

**Loesung:**
Railway cached Docker-Layers. Der erste Build ist immer langsam. Folge-Builds
nutzen den Cache und sind schneller. Falls der Cache nicht genutzt wird:
1. Pruefe ob sich `backend/build.gradle.kts` oder `gradle/libs.versions.toml` geaendert hat
   (das invalidiert den Dependency-Cache-Layer).

---

## 12. Alternative Plattformen

Falls Railway nicht passt, hier sind Alternativen mit dem gleichen Dockerfile:

### Fly.io

```bash
# Fly CLI installieren
brew install flyctl

# Einloggen
fly auth login

# App erstellen (vom Repository-Root)
fly launch --dockerfile backend/Dockerfile --name pushup-backend

# Umgebungsvariablen setzen
fly secrets set KTOR_ENV=production
fly secrets set SUPABASE_JWT_SECRET=dein-secret
fly secrets set JWT_ISSUER=https://dein-ref.supabase.co/auth/v1
fly secrets set DATABASE_URL="jdbc:postgresql://..."

# Deployen
fly deploy --dockerfile backend/Dockerfile
```

Fly.io generiert eine URL wie `https://pushup-backend.fly.dev`.

### Render

1. Gehe zu https://render.com und erstelle einen Account.
2. Klicke **New > Web Service**.
3. Verbinde dein GitHub-Repository.
4. Konfiguriere:
   - **Environment:** Docker
   - **Dockerfile Path:** `backend/Dockerfile`
   - **Branch:** `main`
5. Trage die Umgebungsvariablen unter **Environment Variables** ein.
6. Klicke **Create Web Service**.

Render generiert eine URL wie `https://pushup-backend.onrender.com`.

**Hinweis:** Render Free-Tier spinnt den Service nach 15 Minuten Inaktivitaet herunter.
Der erste Request nach einer Pause dauert dann ~30 Sekunden (Cold Start).
Railway hat dieses Problem nicht.

---

## Checkliste

Hake jeden Punkt ab, sobald du ihn abgeschlossen hast:

### Railway Setup
- [ ] Railway-Account erstellt (GitHub-Login)
- [ ] Neues Railway-Projekt angelegt
- [ ] GitHub-Repository verbunden
- [ ] Service auf Branch `main` konfiguriert
- [ ] Service umbenannt zu `pushup-backend`

### Umgebungsvariablen
- [ ] `KTOR_ENV=production` gesetzt
- [ ] `SUPABASE_JWT_SECRET` gesetzt
- [ ] `JWT_ISSUER` gesetzt (Format: `https://<ref>.supabase.co/auth/v1`)
- [ ] `DATABASE_URL` gesetzt (JDBC-Format mit `sslmode=require`)
- [ ] `CORS_ALLOWED_HOSTS` gesetzt (Railway-URL ohne `https://`)

### Deploy
- [ ] Erster Deploy erfolgreich abgeschlossen
- [ ] Public URL generiert (Railway Networking > Generate Domain)
- [ ] Health-Check erfolgreich: `curl https://deine-url.railway.app/health`

### Auto-Deploy
- [ ] Railway-Token erstellt (https://railway.app/account/tokens)
- [ ] `RAILWAY_TOKEN` als GitHub Secret hinterlegt
- [ ] GitHub Actions Workflow `.github/workflows/deploy.yml` funktioniert
- [ ] Test: Push auf `main` loest automatischen Deploy aus

### Monitoring
- [ ] Logs im Railway-Dashboard geprueft (Tab Logs)
- [ ] Metriken im Railway-Dashboard geprueft (Tab Metrics)
- [ ] (Optional) Alerts konfiguriert

---

## Wichtige URLs nach dem Setup

Trage diese Werte nach dem Deployment ein:

```
Railway Service URL:  https://pushup-backend-production-xxxx.up.railway.app
Health-Check URL:     https://pushup-backend-production-xxxx.up.railway.app/health
Railway Dashboard:    https://railway.app/project/<dein-projekt-id>
```

Die Service-URL wird in der mobilen App (KMP shared module) als `BACKEND_URL`
Umgebungsvariable benoetigt.
