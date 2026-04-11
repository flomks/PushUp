# Apple Developer Account -- Vollstaendige Einrichtungsanleitung

**Stand: Maerz 2026**
**App: PushUp (Bundle ID: `com.flomks.pushup`)**

Diese Anleitung fuehrt dich Schritt fuer Schritt durch die Einrichtung von:
1. Sign In with Apple (fuer den Login-Screen)
2. Apple Push Notifications (APNs) fuer Push-Benachrichtigungen

---

## Voraussetzungen

- Apple Developer Account aktiv (99 USD/Jahr bezahlt)
- Xcode 16+ auf deinem Mac installiert
- Zugriff auf das Supabase Dashboard (`https://supabase.com/dashboard`)
- Zugriff auf deinen Backend-Server (Railway / eigener Server)

---

## Teil 1: Sign In with Apple

### Schritt 1.1 -- App ID konfigurieren (Apple Developer Portal)

1. Oeffne **https://developer.apple.com/account**
2. Klicke links auf **Certificates, Identifiers & Profiles**
3. Klicke auf **Identifiers** (linke Seitenleiste)
4. Suche deine App ID: `com.flomks.pushup`
   - Falls sie noch nicht existiert: Klicke **+**, waehle **App IDs**, dann **App**, klicke **Continue**
   - **Description:** `PushUp`
   - **Bundle ID:** `com.flomks.pushup` (Explicit)
5. Scrolle in der Capabilities-Liste nach unten zu **Sign In with Apple**
6. Setze den Haken bei **Sign In with Apple**
7. Klicke **Edit** neben Sign In with Apple
8. Waehle **Enable as a primary App ID**
9. Klicke **Save**
10. Klicke oben rechts **Continue** und dann **Save** (oder **Register** bei neuer App ID)

### Schritt 1.2 -- Service ID erstellen (fuer Supabase Web-Flow)

Supabase benoetigt eine Service ID als `client_id` fuer den Apple OAuth-Flow.

1. Gehe zu **Certificates, Identifiers & Profiles > Identifiers**
2. Klicke **+** oben rechts
3. Waehle **Services IDs** und klicke **Continue**
4. Fuell aus:
   - **Description:** `PushUp Sign In`
   - **Identifier:** `com.flomks.pushup.signin`
     (muss sich von der App Bundle ID unterscheiden -- `.signin` am Ende)
5. Klicke **Continue** und dann **Register**
6. Klicke auf die neu erstellte Service ID `com.flomks.pushup.signin` in der Liste
7. Aktiviere den Haken bei **Sign In with Apple**
8. Klicke **Configure** neben Sign In with Apple
9. Fuell das Formular aus:
   - **Primary App ID:** `com.flomks.pushup` (deine App ID aus Schritt 1.1)
   - **Domains and Subdomains:** `ptllenkizeipinpuqapl.supabase.co`
   - **Return URLs:**
     ```
     https://ptllenkizeipinpuqapl.supabase.co/auth/v1/callback
     ```
10. Klicke **Next**, dann **Done**
11. Klicke **Continue** und dann **Save**

### Schritt 1.3 -- Private Key fuer Sign In with Apple erstellen

1. Gehe zu **Certificates, Identifiers & Profiles > Keys**
2. Klicke **+** oben rechts
3. Fuell aus:
   - **Key Name:** `PushUp Sign In Key`
4. Aktiviere den Haken bei **Sign In with Apple**
5. Klicke **Configure** neben Sign In with Apple
6. Waehle **Primary App ID:** `com.flomks.pushup`
7. Klicke **Save**
8. Klicke **Continue** und dann **Register**
9. **WICHTIG:** Klicke **Download** -- du kannst den Key nur EINMAL herunterladen!
   Speichere die Datei `AuthKey_XXXXXXXXXX.p8` sicher (z.B. in 1Password oder einem sicheren Ordner)
10. Notiere dir:
    - **Key ID:** der 10-stellige Code (z.B. `ABC1234567`) -- sichtbar auf der Download-Seite
    - **Team ID:** deine 10-stellige Team ID -- sichtbar oben rechts im Developer Portal

### Schritt 1.4 -- Apple Provider in Supabase aktivieren

1. Oeffne **https://supabase.com/dashboard**
2. Waehle dein Projekt (`ptllenkizeipinpuqapl`)
3. Klicke links auf **Authentication**
4. Klicke auf **Providers** (oben in der Auth-Sektion)
5. Suche **Apple** und klicke darauf
6. Aktiviere den Toggle **Enable Apple provider**
7. Fuell die Felder aus:
   - **Service ID (client_id):** `com.flomks.pushup.signin`
   - **Team ID:** deine 10-stellige Team ID (z.B. `YYYYYYYYYY`)
   - **Key ID:** die Key ID aus Schritt 1.3 (z.B. `ABC1234567`)
   - **Private Key:** Oeffne die `.p8`-Datei in einem Texteditor (z.B. TextEdit oder VS Code),
     kopiere den **gesamten Inhalt** inklusive der Header-Zeilen:
     ```
     -----BEGIN PRIVATE KEY-----
     MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg...
     -----END PRIVATE KEY-----
     ```
8. Klicke **Save**

### Schritt 1.5 -- Redirect URL in Supabase eintragen

1. Gehe in Supabase zu **Authentication > URL Configuration**
2. Unter **Redirect URLs** klicke **Add URL**
3. Trage ein:
   ```
   com.flomks.pushup://auth/callback
   ```
4. Klicke **Save**

### Schritt 1.6 -- Team ID in Xcode eintragen

1. Oeffne `iosApp/Configuration/Config.xcconfig` in einem Texteditor
2. Trage deine Team ID ein:
   ```
   TEAM_ID=YYYYYYYYYY
   ```
   (Ersetze `YYYYYYYYYY` mit deiner echten 10-stelligen Team ID)
3. Speichere die Datei

### Schritt 1.7 -- In Xcode: Signing & Capabilities pruefen

1. Oeffne `iosApp/iosApp.xcodeproj` in Xcode
2. Klicke auf das Projekt-Root in der linken Seitenleiste
3. Waehle das Target **iosApp**
4. Gehe zum Tab **Signing & Capabilities**
5. Stelle sicher, dass:
   - **Team:** dein Apple Developer Team ausgewaehlt ist
   - **Bundle Identifier:** `com.flomks.pushup`
   - Die Capability **Sign In with Apple** sichtbar ist
     (wurde durch die Aenderung in `project.pbxproj` und `iosApp.entitlements` hinzugefuegt)
   - Die Capability **Push Notifications** sichtbar ist
6. Falls eine Capability fehlt: Klicke **+ Capability** und fuege sie manuell hinzu

### Testen von Sign In with Apple

1. Baue die App auf einem echten iPhone (Simulator unterstuetzt Sign In with Apple eingeschraenkt)
2. Tippe auf dem Login-Screen auf **Sign in with Apple**
3. Das System-Sheet von Apple erscheint
4. Melde dich mit deiner Apple ID an
5. Die App sollte dich einloggen und zum Hauptscreen navigieren

---

## Teil 2: Apple Push Notifications (APNs)

### Schritt 2.1 -- APNs Key erstellen (Apple Developer Portal)

Du brauchst einen separaten Key fuer APNs (oder du kannst denselben Key wie fuer Sign In with Apple verwenden, wenn du beide Capabilities aktivierst).

**Option A: Neuen Key erstellen (empfohlen -- saubere Trennung)**

1. Gehe zu **Certificates, Identifiers & Profiles > Keys**
2. Klicke **+** oben rechts
3. Fuell aus:
   - **Key Name:** `PushUp APNs Key`
4. Aktiviere den Haken bei **Apple Push Notifications service (APNs)**
5. Klicke **Continue** und dann **Register**
6. **WICHTIG:** Klicke **Download** -- nur einmal moeglich!
   Speichere die Datei `AuthKey_XXXXXXXXXX.p8` sicher
7. Notiere dir:
   - **Key ID:** der 10-stellige Code (z.B. `DEF7890123`)
   - **Team ID:** deine 10-stellige Team ID (gleich wie oben)

**Option B: Bestehenden Key erweitern**

Falls du bereits einen Key fuer Sign In with Apple hast, kannst du APNs nicht nachtraeglich hinzufuegen -- Apple erlaubt keine Aenderung nach der Erstellung. Du musst einen neuen Key erstellen.

### Schritt 2.2 -- APNs Konfiguration auf dem Backend-Server eintragen

Die APNs-Konfiguration wird als Umgebungsvariablen auf dem Backend-Server gesetzt.

**Fuer Railway:**

1. Oeffne dein Railway-Projekt
2. Klicke auf den Backend-Service
3. Gehe zu **Variables**
4. Fuege folgende Variablen hinzu:

```
APNS_KEY_ID=DEF7890123
APNS_TEAM_ID=YYYYYYYYYY
APNS_BUNDLE_ID=com.flomks.pushup
APNS_PRODUCTION=false
APNS_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\nMIGHAgEAMBMG...\n-----END PRIVATE KEY-----
```

**Wichtig fuer `APNS_PRIVATE_KEY`:**
- Oeffne die `.p8`-Datei in einem Texteditor
- Kopiere den gesamten Inhalt
- Ersetze alle echten Zeilenumbrueche durch `\n`
- Das Ergebnis sieht so aus (alles in einer Zeile):
  ```
  -----BEGIN PRIVATE KEY-----\nMIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg...\n-----END PRIVATE KEY-----
  ```

**`APNS_PRODUCTION` Wert:**
- `false` = Sandbox (fuer Development-Builds und TestFlight)
- `true` = Production (fuer App Store Releases)

**Fuer eigenen Server (Docker):**

Trage die Werte in `/opt/pushup/.env` ein (die Datei wird von `docker-compose.yml` geladen).

### Schritt 2.3 -- Push Notifications in der App testen

1. Baue die App auf einem echten iPhone (APNs funktioniert nicht im Simulator)
2. Starte die App
3. Das System fragt nach Erlaubnis fuer Benachrichtigungen -- tippe **Erlauben**
4. Der APNs-Token wird automatisch an den Backend-Server gesendet
5. Pruefe die Backend-Logs: du solltest `APNs token registered with backend` sehen

**Manueller Test mit curl:**

```bash
# Ersetze <JWT> mit einem gueltigen Access Token (aus dem Supabase Dashboard)
# Ersetze <BACKEND_URL> mit deiner Backend-URL (z.B. https://sinura.fun)
curl -X POST https://sinura.fun/v1/device-token \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"token": "test-token-123", "platform": "apns"}'
```

### Schritt 2.4 -- Push Notification senden (Test)

Du kannst eine Test-Push-Notification direkt ueber das Supabase Dashboard senden:

1. Gehe zu **Supabase Dashboard > Authentication > Users**
2. Klicke auf einen User
3. Notiere die User-ID (UUID)

Oder sende direkt ueber den Backend-Endpunkt (falls implementiert).

---

## Teil 3: Supabase -- Apple Sign-In Verbindung pruefen

### Schritt 3.1 -- Apple OAuth in Supabase testen

Nachdem du alles konfiguriert hast, kannst du den Apple Sign-In direkt testen:

1. Gehe zu **Supabase Dashboard > Authentication > Providers > Apple**
2. Pruefe, dass alle Felder ausgefuellt sind:
   - Service ID: `com.flomks.pushup.signin`
   - Team ID: deine Team ID
   - Key ID: deine Key ID
   - Private Key: der Inhalt der `.p8`-Datei

### Schritt 3.2 -- Neuen Apple-User in Supabase pruefen

Nach dem ersten Apple Sign-In:

1. Gehe zu **Supabase Dashboard > Authentication > Users**
2. Du solltest einen neuen User mit:
   - **Provider:** `apple`
   - **Email:** die Apple-Email (oder eine private Relay-Email von Apple)
3. Pruefe im SQL Editor, ob der Trigger den User-Datensatz erstellt hat:

```sql
SELECT u.id, u.email, u.display_name, tc.total_earned_seconds
FROM public.users u
LEFT JOIN public.time_credits tc ON tc.user_id = u.id
WHERE u.id = '<USER-UUID-AUS-AUTH-USERS>';
```

---

## Checkliste

### Sign In with Apple
- [ ] App ID `com.flomks.pushup` hat "Sign In with Apple" aktiviert
- [ ] Service ID `com.flomks.pushup.signin` erstellt und konfiguriert
- [ ] Return URL `https://ptllenkizeipinpuqapl.supabase.co/auth/v1/callback` eingetragen
- [ ] Private Key (.p8) heruntergeladen und sicher gespeichert
- [ ] Key ID und Team ID notiert
- [ ] Supabase: Apple Provider aktiviert mit Service ID, Team ID, Key ID, Private Key
- [ ] Supabase: Redirect URL `com.flomks.pushup://auth/callback` eingetragen
- [ ] `Config.xcconfig`: `TEAM_ID` eingetragen
- [ ] Xcode: Signing & Capabilities zeigt "Sign In with Apple"
- [ ] Test auf echtem iPhone erfolgreich

### Push Notifications (APNs)
- [ ] APNs Key erstellt und heruntergeladen
- [ ] Key ID und Team ID notiert
- [ ] Backend: `APNS_KEY_ID` gesetzt
- [ ] Backend: `APNS_TEAM_ID` gesetzt
- [ ] Backend: `APNS_BUNDLE_ID=com.flomks.pushup` gesetzt
- [ ] Backend: `APNS_PRIVATE_KEY` gesetzt (mit `\n` als Zeilenumbrueche)
- [ ] Backend: `APNS_PRODUCTION=false` (fuer Development) oder `true` (fuer App Store)
- [ ] Test auf echtem iPhone: Benachrichtigungserlaubnis erteilt
- [ ] Backend-Logs zeigen: APNs token registered

---

## Troubleshooting

### "Sign In with Apple" zeigt keinen Button

**Ursache:** Die Capability ist nicht im Xcode-Projekt aktiviert.

**Loesung:**
1. Oeffne Xcode > Target > Signing & Capabilities
2. Klicke **+ Capability** > **Sign In with Apple**
3. Stelle sicher, dass `iosApp.entitlements` den Eintrag `com.apple.developer.applesignin` enthaelt

### "invalid_client" Fehler bei Apple Sign-In

**Ursache:** Service ID, Team ID oder Key ID falsch in Supabase eingetragen.

**Loesung:**
1. Pruefe alle drei Werte im Apple Developer Portal
2. Vergleiche sie mit den Eintraegen in Supabase > Authentication > Providers > Apple
3. Stelle sicher, dass die Return URL exakt `https://ptllenkizeipinpuqapl.supabase.co/auth/v1/callback` ist

### APNs Token wird nicht registriert

**Ursache 1:** App laeuft im Simulator (APNs funktioniert nur auf echten Geraeten).

**Ursache 2:** `APNS_KEY_ID`, `APNS_TEAM_ID` oder `APNS_PRIVATE_KEY` fehlen auf dem Server.

**Loesung:**
1. Pruefe die Backend-Logs auf Warnungen wie `APNs not configured`
2. Stelle sicher, dass alle 4 Umgebungsvariablen gesetzt sind
3. Starte den Backend-Service neu nach dem Setzen der Variablen

### Push Notification kommt nicht an

**Ursache 1:** `APNS_PRODUCTION=true` aber App ist ein Development-Build (oder umgekehrt).

**Loesung:**
- Development-Builds (direkt aus Xcode): `APNS_PRODUCTION=false`
- TestFlight-Builds: `APNS_PRODUCTION=false`
- App Store-Builds: `APNS_PRODUCTION=true`

**Ursache 2:** APNs-Token ist abgelaufen oder gehoert einem anderen Geraet.

**Loesung:** Starte die App neu -- iOS liefert automatisch einen neuen Token.

### "The operation couldn't be completed" bei Apple Sign-In

**Ursache:** Die App laeuft auf einem Simulator oder das Geraet ist nicht mit einer Apple ID angemeldet.

**Loesung:** Teste auf einem echten iPhone, das mit einer Apple ID angemeldet ist.

---

## Wichtige Werte (nach der Konfiguration ausfuellen)

```
Apple Developer Team ID:    ____________________
Sign In with Apple Key ID:  ____________________
APNs Key ID:                ____________________
Service ID:                 com.flomks.pushup.signin
Bundle ID:                  com.flomks.pushup
Supabase Project:           ptllenkizeipinpuqapl
```

**Sicherheitshinweis:** Speichere die `.p8`-Dateien niemals im Git-Repository.
Verwende einen Passwort-Manager (1Password, Bitwarden) oder einen sicheren Datei-Speicher.
