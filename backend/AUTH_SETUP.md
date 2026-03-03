# Supabase Auth Setup -- Schritt-fuer-Schritt Anleitung

Dieses Dokument beschreibt **jeden manuellen Schritt**, den du im Supabase Dashboard
ausfuehren musst, um Email-Login, Apple Sign-In und Google Sign-In fuer die PushUp App
zu konfigurieren.

Voraussetzung: Du hast bereits ein Supabase-Projekt erstellt und die Migration
`001_initial_schema.sql` ausgefuehrt (siehe `backend/README.md`).

---

## Inhaltsverzeichnis

1. [Email Auth aktivieren](#1-email-auth-aktivieren)
2. [Google Sign-In konfigurieren](#2-google-sign-in-konfigurieren)
3. [Apple Sign-In konfigurieren](#3-apple-sign-in-konfigurieren)
4. [Auth Callbacks und Deep Links konfigurieren](#4-auth-callbacks-und-deep-links-konfigurieren)
5. [RLS Policies pruefen](#5-rls-policies-pruefen)
6. [Registrierung via Email testen](#6-registrierung-via-email-testen)
7. [Checkliste](#7-checkliste)

---

## 1. Email Auth aktivieren

### 1.1 Email + Passwort aktivieren

1. Oeffne dein Supabase-Projekt unter **https://supabase.com/dashboard**.
2. Klicke in der linken Seitenleiste auf **Authentication**.
3. Klicke auf **Providers** (oben in der Auth-Sektion).
4. Suche den Eintrag **Email** und klicke darauf.
5. Stelle sicher, dass der Toggle **Enable Email provider** auf **AN** (blau) steht.
6. Aktiviere **Enable Email Signup** (Benutzer koennen sich selbst registrieren).
7. Aktiviere **Confirm email** -- Benutzer muessen ihre E-Mail-Adresse bestaetigen,
   bevor sie sich einloggen koennen. (Empfohlen fuer Produktion.)
8. Klicke **Save**.

### 1.2 Email Magic Link aktivieren

Magic Links erlauben passwortlosen Login per E-Mail-Link.

1. Bleibe auf der Seite **Authentication > Providers > Email**.
2. Der Magic Link ist automatisch aktiv, sobald Email aktiviert ist.
   Es gibt keine separate Einstellung -- Magic Links werden ueber die
   Supabase-Client-Methode `signInWithOtp({ email })` ausgeloest.
3. Optional: Passe die **OTP Expiry** (Ablaufzeit des Links) an.
   - Gehe zu **Authentication > Settings** (Zahnrad-Icon oder "Settings"-Tab).
   - Suche **OTP Expiry** und setze den Wert (Standard: 3600 Sekunden = 1 Stunde).
   - Klicke **Save**.

### 1.3 E-Mail-Templates anpassen (optional, empfohlen)

1. Gehe zu **Authentication > Email Templates**.
2. Du siehst folgende Templates:
   - **Confirm signup** -- wird nach der Registrierung gesendet
   - **Magic Link** -- wird beim passwortlosen Login gesendet
   - **Change Email Address** -- wird bei E-Mail-Aenderung gesendet
   - **Reset Password** -- wird beim Passwort-Zuruecksetzen gesendet
3. Klicke auf **Confirm signup** und passe den Text an (App-Name, Sprache, etc.).
4. Wichtig: Behalte den Platzhalter `{{ .ConfirmationURL }}` im Template -- das ist
   der eigentliche Bestaetigunslink.
5. Klicke **Save** nach jeder Aenderung.

---

## 2. Google Sign-In konfigurieren

### 2.1 Google Cloud Console -- OAuth-Credentials erstellen

Du brauchst ein Google-Konto und Zugriff auf die Google Cloud Console.

**Schritt A: Projekt erstellen oder auswaehlen**

1. Oeffne **https://console.cloud.google.com**.
2. Klicke oben links auf das Projekt-Dropdown und waehle ein bestehendes Projekt
   oder klicke **Neues Projekt** und erstelle eines (z.B. `pushup-app`).

**Schritt B: OAuth-Zustimmungsbildschirm konfigurieren**

1. Gehe im linken Menue zu **APIs & Dienste > OAuth-Zustimmungsbildschirm**.
2. Waehle **Extern** (fuer oeffentliche Apps) und klicke **Erstellen**.
3. Fuell die Pflichtfelder aus:
   - **App-Name:** `PushUp App`
   - **Nutzersupport-E-Mail:** deine E-Mail-Adresse
   - **Entwicklerkontakt-E-Mail:** deine E-Mail-Adresse
4. Klicke **Speichern und fortfahren** (durch alle Schritte bis zum Ende).
5. Klicke **Zurueck zum Dashboard**.

**Schritt C: OAuth 2.0-Client-ID erstellen**

1. Gehe zu **APIs & Dienste > Anmeldedaten**.
2. Klicke **+ Anmeldedaten erstellen > OAuth-Client-ID**.
3. Waehle als Anwendungstyp: **iOS** (fuer die iOS-App).
   - **Bundle-ID:** `com.yourcompany.pushupapp`
     (muss exakt mit deiner Xcode-Bundle-ID uebereinstimmen)
   - Klicke **Erstellen**.
   - Notiere die **Client-ID** (sieht aus wie `123456789-abc...apps.googleusercontent.com`).
4. Erstelle eine zweite Client-ID fuer **Web** (wird von Supabase benoetigt):
   - Klicke erneut **+ Anmeldedaten erstellen > OAuth-Client-ID**.
   - Waehle **Webanwendung**.
   - **Name:** `PushUp App Web`
   - Unter **Autorisierte Weiterleitungs-URIs** klicke **+ URI hinzufuegen** und trage ein:
     ```
     https://<DEIN-PROJEKT-REF>.supabase.co/auth/v1/callback
     ```
     (Ersetze `<DEIN-PROJEKT-REF>` mit deiner Supabase-Projekt-Referenz,
     z.B. `xyzxyzxyz`. Die findest du in der Supabase-URL deines Projekts.)
   - Klicke **Erstellen**.
   - Notiere **Client-ID** und **Client-Secret** der Web-Anwendung.

### 2.2 Google Provider in Supabase aktivieren

1. Gehe in deinem Supabase-Dashboard zu **Authentication > Providers**.
2. Suche **Google** und klicke darauf.
3. Aktiviere den Toggle **Enable Google provider**.
4. Trage ein:
   - **Client ID (for iOS):** die iOS-Client-ID aus Schritt C (Punkt 3 oben)
   - **Client ID:** die Web-Client-ID aus Schritt C (Punkt 4 oben)
   - **Client Secret:** das Web-Client-Secret aus Schritt C (Punkt 4 oben)
5. Klicke **Save**.

---

## 3. Apple Sign-In konfigurieren

Apple Sign-In erfordert einen **Apple Developer Account** (99 USD/Jahr).

### 3.1 Apple Developer Portal -- App ID konfigurieren

1. Oeffne **https://developer.apple.com/account**.
2. Gehe zu **Certificates, Identifiers & Profiles > Identifiers**.
3. Klicke auf deine App-ID (z.B. `com.yourcompany.pushupapp`).
   Falls noch keine existiert, klicke **+** und erstelle eine neue App-ID.
4. Scrolle in der Liste der Capabilities nach unten zu **Sign In with Apple**.
5. Setze den Haken bei **Sign In with Apple**.
6. Klicke **Edit** neben Sign In with Apple.
7. Waehle **Enable as a primary App ID**.
8. Klicke **Save** und dann **Continue** und **Register**.

### 3.2 Apple Developer Portal -- Service ID erstellen

Die Service ID wird als `client_id` fuer den Web-OAuth-Flow benoetigt (Supabase nutzt diesen).

1. Gehe zu **Certificates, Identifiers & Profiles > Identifiers**.
2. Klicke **+** oben rechts.
3. Waehle **Services IDs** und klicke **Continue**.
4. Fuell aus:
   - **Description:** `PushUp App Sign In`
   - **Identifier:** `com.yourcompany.pushupapp.signin`
     (muss sich von der App-Bundle-ID unterscheiden)
5. Klicke **Continue** und dann **Register**.
6. Klicke auf die neu erstellte Service ID in der Liste.
7. Aktiviere den Haken bei **Sign In with Apple**.
8. Klicke **Configure** neben Sign In with Apple.
9. Fuell aus:
   - **Primary App ID:** waehle deine App-ID (`com.yourcompany.pushupapp`)
   - **Domains and Subdomains:** `<DEIN-PROJEKT-REF>.supabase.co`
   - **Return URLs:** 
     ```
     https://<DEIN-PROJEKT-REF>.supabase.co/auth/v1/callback
     ```
10. Klicke **Next** und dann **Done** und dann **Continue** und **Save**.

### 3.3 Apple Developer Portal -- Private Key erstellen

1. Gehe zu **Certificates, Identifiers & Profiles > Keys**.
2. Klicke **+** oben rechts.
3. Fuell aus:
   - **Key Name:** `PushUp App Sign In Key`
4. Aktiviere den Haken bei **Sign In with Apple**.
5. Klicke **Configure** neben Sign In with Apple.
6. Waehle deine **Primary App ID** (`com.yourcompany.pushupapp`).
7. Klicke **Save**.
8. Klicke **Continue** und dann **Register**.
9. **WICHTIG:** Klicke **Download** -- du kannst den Key nur EINMAL herunterladen.
   Speichere die `.p8`-Datei sicher (z.B. `AuthKey_XXXXXXXXXX.p8`).
10. Notiere die **Key ID** (10-stelliger alphanumerischer Code, z.B. `XXXXXXXXXX`).
11. Notiere deine **Team ID** (findest du oben rechts im Developer Portal, z.B. `YYYYYYYYYY`).

### 3.4 Apple Provider in Supabase aktivieren

1. Gehe in deinem Supabase-Dashboard zu **Authentication > Providers**.
2. Suche **Apple** und klicke darauf.
3. Aktiviere den Toggle **Enable Apple provider**.
4. Trage ein:
   - **Service ID (client_id):** die Service ID aus Schritt 3.2
     (z.B. `com.yourcompany.pushupapp.signin`)
   - **Team ID:** deine Apple Team ID (z.B. `YYYYYYYYYY`)
   - **Key ID:** die Key ID aus Schritt 3.3 (z.B. `XXXXXXXXXX`)
   - **Private Key:** oeffne die heruntergeladene `.p8`-Datei in einem Texteditor,
     kopiere den gesamten Inhalt (inkl. `-----BEGIN PRIVATE KEY-----` und
     `-----END PRIVATE KEY-----`) und fuege ihn hier ein.
5. Klicke **Save**.

---

## 4. Auth Callbacks und Deep Links konfigurieren

### 4.1 Redirect URLs in Supabase eintragen

Supabase muss wissen, welche URLs nach einem erfolgreichen Login erlaubt sind.

1. Gehe zu **Authentication > URL Configuration**.
2. **Site URL:** Trage die URL deiner Web-App ein (falls vorhanden), z.B.:
   ```
   https://pushupapp.com
   ```
   Fuer reine Mobile-Apps kannst du hier einen Platzhalter eintragen:
   ```
   https://pushupapp.com
   ```
3. **Redirect URLs:** Klicke **Add URL** und trage folgende URLs ein
   (eine pro Zeile, jeweils als separate Eintraege):

   Fuer iOS Deep Links (Universal Links oder Custom URL Scheme):
   ```
   com.yourcompany.pushupapp://auth/callback
   ```
   Fuer Android Deep Links:
   ```
   com.yourcompany.pushupapp://auth/callback
   ```
   Fuer lokale Entwicklung (Simulator/Emulator):
   ```
   exp://localhost:8081/--/auth/callback
   ```
   Fuer Expo Go (falls du Expo nutzt):
   ```
   exp://127.0.0.1:8081/--/auth/callback
   ```

4. Klicke **Save**.

### 4.2 iOS -- URL Scheme in Xcode konfigurieren

Diese Schritte fuehrst du in Xcode aus (nicht im Supabase Dashboard):

1. Oeffne dein Xcode-Projekt (`iosApp/`).
2. Klicke auf das Projekt-Root in der linken Seitenleiste.
3. Waehle dein App-Target.
4. Gehe zum Tab **Info**.
5. Scrolle nach unten zu **URL Types**.
6. Klicke **+** und trage ein:
   - **Identifier:** `com.yourcompany.pushupapp`
   - **URL Schemes:** `com.yourcompany.pushupapp`
7. Speichere (Cmd+S).

Damit kann die App nach dem OAuth-Login vom Browser zurueck zur App weitergeleitet werden.

### 4.3 iOS -- Associated Domains fuer Universal Links (optional, empfohlen)

Falls du Universal Links statt Custom URL Schemes nutzen moechtest:

1. Gehe in Xcode zu deinem App-Target > **Signing & Capabilities**.
2. Klicke **+ Capability** und waehle **Associated Domains**.
3. Klicke **+** unter Associated Domains und trage ein:
   ```
   applinks:<DEIN-PROJEKT-REF>.supabase.co
   ```
4. Im Apple Developer Portal unter deiner App-ID: aktiviere **Associated Domains**.

---

## 5. RLS Policies pruefen

Die Row Level Security Policies wurden bereits in `001_initial_schema.sql` erstellt.
Fuehre folgende Queries im **SQL Editor** des Supabase Dashboards aus, um zu pruefen,
dass alles korrekt konfiguriert ist.

### 5.1 Alle Tabellen und RLS-Status pruefen

Oeffne **SQL Editor > New query**, fuege ein und klicke **Run**:

```sql
SELECT
  tablename,
  rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
```

**Erwartetes Ergebnis:** Alle 5 Tabellen zeigen `rls_enabled = true`:

| tablename         | rls_enabled |
|-------------------|-------------|
| push_up_records   | true        |
| time_credits      | true        |
| user_settings     | true        |
| users             | true        |
| workout_sessions  | true        |

### 5.2 Alle RLS Policies auflisten

```sql
SELECT
  schemaname,
  tablename,
  policyname,
  cmd AS operation,
  qual AS using_expression,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;
```

**Erwartetes Ergebnis:** Du siehst mindestens diese Policies:

| tablename         | policyname                        | operation |
|-------------------|-----------------------------------|-----------|
| push_up_records   | push_up_records_delete_own        | DELETE    |
| push_up_records   | push_up_records_insert_own        | INSERT    |
| push_up_records   | push_up_records_select_own        | SELECT    |
| push_up_records   | push_up_records_update_own        | UPDATE    |
| time_credits      | time_credits_insert_own           | INSERT    |
| time_credits      | time_credits_select_own           | SELECT    |
| time_credits      | time_credits_update_own           | UPDATE    |
| user_settings     | user_settings_insert_own          | INSERT    |
| user_settings     | user_settings_select_own          | SELECT    |
| user_settings     | user_settings_update_own          | UPDATE    |
| users             | users_select_own                  | SELECT    |
| users             | users_update_own                  | UPDATE    |
| workout_sessions  | workout_sessions_delete_own       | DELETE    |
| workout_sessions  | workout_sessions_insert_own       | INSERT    |
| workout_sessions  | workout_sessions_select_own       | SELECT    |
| workout_sessions  | workout_sessions_update_own       | UPDATE    |

### 5.3 Auth-Trigger pruefen

```sql
SELECT
  trigger_name,
  event_manipulation,
  event_object_schema,
  event_object_table,
  action_timing
FROM information_schema.triggers
WHERE trigger_name = 'trg_on_auth_user_created';
```

**Erwartetes Ergebnis:** 1 Zeile mit `trigger_name = trg_on_auth_user_created`,
`event_object_schema = auth`, `event_object_table = users`.

### 5.4 Nur authentifizierte User haben Zugriff -- manuell pruefen

1. Gehe zu **Authentication > Policies** (oder **Table Editor > [Tabelle] > Policies**).
2. Klicke auf eine Tabelle, z.B. `workout_sessions`.
3. Du siehst die 4 Policies (SELECT, INSERT, UPDATE, DELETE).
4. Jede Policy hat als Bedingung `auth.uid() = user_id` -- das stellt sicher,
   dass nur eingeloggte User auf ihre eigenen Daten zugreifen koennen.
5. Unauthentifizierte Anfragen (ohne JWT) werden automatisch abgelehnt.

---

## 6. Registrierung via Email testen

### 6.1 Test-Benutzer im Dashboard erstellen

1. Gehe zu **Authentication > Users**.
2. Klicke **Add user > Create new user**.
3. Trage ein:
   - **Email:** `test@example.com`
   - **Password:** `Test1234!`
   - **Auto Confirm User:** Haken setzen (damit du nicht auf die Bestaetigunsmail warten musst)
4. Klicke **Create user**.
5. Du siehst den neuen User in der Liste.

### 6.2 Pruefen ob der Trigger funktioniert hat

Nach der Erstellung des Users sollte der Trigger `trg_on_auth_user_created` automatisch
Zeilen in `public.users`, `public.time_credits` und `public.user_settings` erstellt haben.

Fuehre im SQL Editor aus:

```sql
-- Ersetze die UUID mit der ID des soeben erstellten Users
-- (sichtbar in Authentication > Users)
SELECT u.id, u.email, tc.total_earned_seconds, us.push_ups_per_minute_credit
FROM public.users u
LEFT JOIN public.time_credits tc ON tc.user_id = u.id
LEFT JOIN public.user_settings us ON us.user_id = u.id
WHERE u.email = 'test@example.com';
```

**Erwartetes Ergebnis:** 1 Zeile mit `total_earned_seconds = 0` und
`push_ups_per_minute_credit = 10`.

### 6.3 Login via Supabase Dashboard testen (API-Test)

Du kannst den Login direkt ueber die Supabase REST API testen:

1. Gehe zu **API Docs** (Buch-Icon in der linken Seitenleiste).
2. Klicke auf **Authentication**.
3. Suche den Endpunkt **Sign in with email and password**.
4. Klicke **Try it out** (falls verfuegbar) oder nutze curl:

```bash
curl -X POST 'https://<DEIN-PROJEKT-REF>.supabase.co/auth/v1/token?grant_type=password' \
  -H "apikey: <DEIN-ANON-KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "Test1234!"
  }'
```

**Erwartetes Ergebnis:** JSON-Antwort mit `access_token`, `refresh_token` und
`user`-Objekt. Kein Fehler.

### 6.4 Magic Link testen

```bash
curl -X POST 'https://<DEIN-PROJEKT-REF>.supabase.co/auth/v1/otp' \
  -H "apikey: <DEIN-ANON-KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com"
  }'
```

**Erwartetes Ergebnis:** `{}` (leere Antwort = Erfolg). Die E-Mail wird gesendet.
Pruefe dein Postfach (oder in Supabase unter **Authentication > Logs**).

---

## 7. Checkliste

Hake jeden Punkt ab, sobald du ihn abgeschlossen hast:

### Email Auth
- [ ] Email Provider aktiviert (Authentication > Providers > Email)
- [ ] "Enable Email Signup" aktiviert
- [ ] "Confirm email" aktiviert
- [ ] OTP Expiry geprueft / angepasst (Authentication > Settings)
- [ ] E-Mail-Templates angepasst (Authentication > Email Templates)

### Google Sign-In
- [ ] Google Cloud Console: OAuth-Zustimmungsbildschirm konfiguriert
- [ ] Google Cloud Console: iOS Client-ID erstellt
- [ ] Google Cloud Console: Web Client-ID + Secret erstellt
- [ ] Supabase: Google Provider aktiviert mit Client-ID und Secret
- [ ] Redirect URI in Google Cloud Console eingetragen

### Apple Sign-In
- [ ] Apple Developer Portal: App-ID hat "Sign In with Apple" aktiviert
- [ ] Apple Developer Portal: Service ID erstellt und konfiguriert
- [ ] Apple Developer Portal: Private Key (.p8) erstellt und heruntergeladen
- [ ] Supabase: Apple Provider aktiviert mit Service ID, Team ID, Key ID, Private Key
- [ ] Redirect URL in Apple Service ID eingetragen

### Deep Links / Callbacks
- [ ] Supabase: Redirect URLs konfiguriert (Authentication > URL Configuration)
- [ ] Xcode: URL Scheme eingetragen (com.yourcompany.pushupapp)
- [ ] (Optional) Xcode: Associated Domains konfiguriert

### RLS Policies
- [ ] SQL-Query ausgefuehrt: alle 5 Tabellen haben RLS aktiviert
- [ ] SQL-Query ausgefuehrt: alle 16 Policies sind vorhanden
- [ ] SQL-Query ausgefuehrt: Trigger trg_on_auth_user_created existiert

### Test
- [ ] Test-User im Dashboard erstellt (Auto Confirm)
- [ ] SQL-Query: User-Zeile + time_credits + user_settings wurden automatisch erstellt
- [ ] curl-Test: Email + Passwort Login gibt access_token zurueck
- [ ] curl-Test: Magic Link OTP wird gesendet (kein Fehler)

---

## Wichtige Werte zum Notieren

Trage diese Werte nach der Konfiguration in deine `.env`-Datei ein
(niemals ins Repository committen):

```bash
# Supabase
SUPABASE_URL=https://<DEIN-PROJEKT-REF>.supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...   # nur serverseitig verwenden

# Google OAuth (fuer KMP / iOS)
GOOGLE_IOS_CLIENT_ID=123456789-abc...apps.googleusercontent.com
GOOGLE_WEB_CLIENT_ID=123456789-xyz...apps.googleusercontent.com

# Apple Sign-In
APPLE_SERVICE_ID=com.yourcompany.pushupapp.signin
APPLE_TEAM_ID=YYYYYYYYYY
APPLE_KEY_ID=XXXXXXXXXX
# Den Private Key (.p8 Inhalt) nicht in .env speichern -- sicher verwahren!
```

---

## Troubleshooting

**"Email not confirmed"**
Der User hat die Bestaetigunsmail nicht geklickt. Im Dashboard unter
Authentication > Users kannst du den User manuell bestaetigen (Klick auf den User
> "Confirm email").

**"Invalid login credentials"**
Falsches Passwort oder E-Mail nicht vorhanden. Pruefe unter Authentication > Users.

**"redirect_uri_mismatch" bei Google**
Die Redirect URI in der Google Cloud Console stimmt nicht mit der Supabase-URL ueberein.
Pruefe: `https://<DEIN-PROJEKT-REF>.supabase.co/auth/v1/callback` muss exakt so
in den "Autorisierten Weiterleitungs-URIs" stehen.

**"invalid_client" bei Apple**
Service ID, Team ID oder Key ID falsch eingetragen. Pruefe alle drei Werte im
Apple Developer Portal und in Supabase.

**Trigger hat keine Zeilen erstellt**
Pruefe ob der Trigger existiert (SQL-Query in Abschnitt 5.3). Falls nicht, fuehre
die Migration `001_initial_schema.sql` erneut aus (nur den Trigger-Teil).

**Deep Link oeffnet nicht die App**
Pruefe ob der URL Scheme in Xcode korrekt eingetragen ist und ob die Redirect URL
in Supabase exakt mit dem URL Scheme uebereinstimmt (Gross-/Kleinschreibung beachten).
