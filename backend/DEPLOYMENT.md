# PushUp Backend -- Deployment-Anleitung (Root-Server)

Das Ktor-Backend laeuft auf einem eigenen Root-Server hinter Nginx.
Die Domain ist `pushup.weareo.fun`.

Der Deploy-Prozess ist vollautomatisch:
**Push auf `main`** --> GitHub Actions baut Docker-Image --> pusht zu GHCR --> SSH auf Server --> neuer Container laeuft.

---

## Architektur

```
Internet
   |
   | HTTPS (443)
   v
Nginx (Reverse Proxy)
   |  pushup.weareo.fun --> localhost:8080
   v
Docker Container: pushup-backend
   |
   v
Supabase PostgreSQL (Cloud)
```

---

## Einmaliges Server-Setup

Diese Schritte fuehrst du **einmalig** auf dem Root-Server aus.

### Schritt 1 -- Verzeichnis anlegen und .env erstellen

```bash
sudo mkdir -p /opt/pushup
sudo chown $USER:$USER /opt/pushup

# docker-compose.yml vom Repo auf den Server kopieren
cp docker-compose.yml /opt/pushup/docker-compose.yml

# .env Datei erstellen (NIEMALS ins Repo committen)
cat > /opt/pushup/.env << 'EOF'
KTOR_ENV=production
PORT=8080
HOST=0.0.0.0

# Supabase Projekt-URL (fuer JWKS/RS256 -- neue Projekte 2025+)
# Supabase Dashboard > Project Settings > API > Project URL
SUPABASE_URL=https://dein-ref.supabase.co

# JWT Secret (nur fuer Legacy-Projekte mit HS256 -- vor 2025)
# Supabase Dashboard > Settings > API > JWT Settings > JWT Secret
# Bei neuen Projekten (RS256) weglassen oder auskommentieren:
# SUPABASE_JWT_SECRET=dein-jwt-secret-hier

# Format: https://<ref>.supabase.co/auth/v1
JWT_ISSUER=https://dein-ref.supabase.co/auth/v1

# Supabase Dashboard > Settings > Database > Connection string > JDBC
DATABASE_URL=jdbc:postgresql://db.dein-ref.supabase.co:5432/postgres?user=postgres&password=dein-passwort&sslmode=require

# Nur HTTPS erlauben in Production
CORS_ALLOWED_HOSTS=pushup.weareo.fun
EOF
```

### Schritt 2 -- GitHub Container Registry Login

Das Docker-Image wird auf `ghcr.io` (GitHub Container Registry) gespeichert.
Damit der Server es pullen kann, musst du dich einmalig einloggen:

```bash
# GitHub Personal Access Token benoetigt (Scope: read:packages)
# Erstellen unter: https://github.com/settings/tokens/new
echo "DEIN_GITHUB_TOKEN" | docker login ghcr.io -u flomks --password-stdin
```

### Schritt 3 -- Nginx-Config einrichten

```bash
# Config-Datei kopieren
sudo cp nginx/pushup.weareo.fun.conf /etc/nginx/sites-available/pushup.weareo.fun

# Aktivieren
sudo ln -s /etc/nginx/sites-available/pushup.weareo.fun /etc/nginx/sites-enabled/

# Syntax pruefen
sudo nginx -t

# Nginx neu laden
sudo systemctl reload nginx
```

### Schritt 4 -- SSL-Zertifikat mit Certbot holen

```bash
# Certbot installieren (falls noch nicht vorhanden)
sudo apt install certbot python3-certbot-nginx -y

# Zertifikat fuer pushup.weareo.fun holen
sudo certbot --nginx -d pushup.weareo.fun

# Certbot traegt SSL automatisch in die Nginx-Config ein
# Automatische Erneuerung pruefen:
sudo certbot renew --dry-run
```

### Schritt 5 -- DNS-Eintrag setzen

Bei deinem Domain-Anbieter (wo weareo.fun verwaltet wird):

```
Typ:   A
Name:  pushup
Wert:  <IP-Adresse deines Root-Servers>
TTL:   300
```

Warten bis der DNS propagiert ist (meist 1-5 Minuten, max. 24h).
Pruefen mit: `dig pushup.weareo.fun`

### Schritt 6 -- Ersten Container manuell starten

```bash
cd /opt/pushup

# Image ziehen und Container starten
docker compose up -d

# Logs pruefen
docker compose logs -f

# Health-Check
curl http://localhost:8080/health
# Erwartete Antwort: {"status":"ok"}
```

---

## GitHub Actions einrichten (Auto-Deploy)

### Schritt 1 -- SSH-Key fuer GitHub Actions erstellen

Auf dem Server einen dedizierten SSH-Key fuer GitHub Actions erstellen:

```bash
# Key erstellen (kein Passwort setzen -- Enter druecken)
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/github_actions_deploy

# Public Key zu authorized_keys hinzufuegen
cat ~/.ssh/github_actions_deploy.pub >> ~/.ssh/authorized_keys

# Private Key anzeigen -- diesen in GitHub Secrets eintragen
cat ~/.ssh/github_actions_deploy
```

### Schritt 2 -- GitHub Secrets hinterlegen

Gehe zu: **GitHub Repository > Settings > Secrets and variables > Actions**

Folgende Secrets anlegen:

| Secret Name | Wert |
|-------------|------|
| `SERVER_HOST` | IP-Adresse deines Root-Servers |
| `SERVER_USER` | SSH-Benutzername (z.B. `root` oder `ubuntu`) |
| `SERVER_SSH_KEY` | Inhalt von `~/.ssh/github_actions_deploy` (komplett mit `-----BEGIN...-----END-----`) |
| `SERVER_PORT` | SSH-Port (Standard: `22`, weglassen wenn 22) |

### Schritt 3 -- Workflow testen

```bash
# Leeren Commit pushen um Deploy auszuloesen
git commit --allow-empty -m "test: trigger deploy"
git push origin main
```

Dann unter **GitHub > Actions > Build & Deploy to Root Server** den Workflow beobachten.

---

## Taegliche Nutzung

### Deploy ausloesen

Einfach auf `main` pushen -- der Workflow laeuft automatisch wenn Dateien in `backend/` geaendert wurden.

### Logs auf dem Server anschauen

```bash
# Live-Logs
docker compose -f /opt/pushup/docker-compose.yml logs -f

# Letzte 100 Zeilen
docker compose -f /opt/pushup/docker-compose.yml logs --tail=100
```

### Container-Status pruefen

```bash
docker compose -f /opt/pushup/docker-compose.yml ps
```

### Manuell neu starten

```bash
cd /opt/pushup && docker compose restart pushup-backend
```

### Manuell auf neue Version updaten

```bash
cd /opt/pushup
docker compose pull
docker compose up -d
```

---

## Health-Check verifizieren

```bash
# Von aussen (nach DNS + SSL Setup)
curl https://pushup.weareo.fun/health
# Erwartete Antwort: {"status":"ok"}

# Direkt auf dem Server
curl http://localhost:8080/health
# Erwartete Antwort: {"status":"ok"}
```

---

## Umgebungsvariablen

Alle Variablen stehen in `/opt/pushup/.env` auf dem Server.
**Diese Datei niemals ins Git-Repository committen.**

| Variable | Beschreibung | Wo finden |
|----------|-------------|-----------|
| `KTOR_ENV` | `production` | Fester Wert |
| `SUPABASE_URL` | Projekt-URL fuer JWKS-Endpoint (neue Projekte, RS256) | Supabase > Project Settings > API |
| `SUPABASE_JWT_SECRET` | JWT Secret (nur Legacy-Projekte mit HS256) | Supabase > Settings > API > JWT Settings |
| `JWT_ISSUER` | `https://<ref>.supabase.co/auth/v1` | Supabase Projekt-URL |
| `DATABASE_URL` | JDBC Connection String | Supabase > Settings > Database > JDBC |
| `CORS_ALLOWED_HOSTS` | `pushup.weareo.fun` | Deine Domain |

**JWT-Verifikation -- welche Variable setzen?**

- **Neues Projekt (2025+, RS256):** Nur `SUPABASE_URL` setzen. Der Backend holt die Public Keys automatisch vom JWKS-Endpoint. `SUPABASE_JWT_SECRET` weglassen.
- **Legacy-Projekt (vor 2025, HS256):** Nur `SUPABASE_JWT_SECRET` setzen. `SUPABASE_URL` ist optional.
- Wenn beide gesetzt sind, hat `SUPABASE_URL` (JWKS) Vorrang.

Nach Aenderung der `.env` Datei Container neu starten:
```bash
cd /opt/pushup && docker compose up -d
```

---

## Troubleshooting

### Container startet nicht

```bash
docker compose -f /opt/pushup/docker-compose.yml logs pushup-backend
```

Haeufige Ursachen:
- `DATABASE_URL` falsch -- JDBC-Format pruefen, Passwort URL-encoden bei Sonderzeichen
- `SUPABASE_JWT_SECRET` fehlt -- `.env` Datei pruefen

### Nginx gibt 502 Bad Gateway

Der Container laeuft nicht oder ist noch nicht bereit:
```bash
docker compose -f /opt/pushup/docker-compose.yml ps
curl http://localhost:8080/health
```

### SSL-Zertifikat abgelaufen

```bash
sudo certbot renew
sudo systemctl reload nginx
```

### Image kann nicht gepullt werden

```bash
# Erneut bei GHCR einloggen
echo "GITHUB_TOKEN" | docker login ghcr.io -u flomks --password-stdin
```
