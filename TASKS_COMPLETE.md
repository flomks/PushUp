# PushUp App -- Vollstaendige Task-Liste (mit Backend, User-Accounts, Cloud-Sync)

Diese Task-Liste enthaelt ALLE Tasks fuer die komplette PushUp-App inklusive:
- Backend mit Supabase + Ktor
- User-Accounts mit Authentication
- Cloud-Synchronisation
- Detaillierte Statistiken (taeglich, woechentlich, monatlich)
- Schoene UIs fuer alle Screens
- Social Features (spaeter)

**Tech-Stack:**
- **Frontend:** iOS (SwiftUI) + Android (Jetpack Compose spaeter)
- **Shared Core:** Kotlin Multiplatform (Business-Logik, API-Client, lokale DB)
- **Backend:** Supabase (Auth, PostgreSQL, Auto-API) + Ktor (Custom-Logik)
- **Datenbank:** PostgreSQL (via Supabase)
- **Auth:** Supabase Auth (Email, Apple Sign-In, Google Sign-In)

---
---

# PHASE 1A: KMP Core & Lokale Funktionalitaet

**Ziel:** Das KMP-Grundgeruest steht, lokale Business-Logik funktioniert (ohne Backend). Daten werden lokal gespeichert.

---

## Task 1A.1: KMP Projekt-Grundgeruest aufsetzen

**Beschreibung:**
Erstelle das Kotlin Multiplatform Projekt mit Gradle. Module: `shared` (KMP Core), `iosApp`, `androidApp` (erstmal leer). Konfiguriere Kotlin, Coroutines, DateTime, Serialization.

**Akzeptanzkriterien:**
- Gradle Multi-Modul-Projekt mit shared/, iosApp/, androidApp/
- shared/src/commonMain, commonTest, iosMain, androidMain sind angelegt
- Dependencies: Kotlin 2.0+, Coroutines, kotlinx-datetime, kotlinx-serialization
- "Hello World" Test in commonTest laeuft durch
- .gitignore konfiguriert (build/, .gradle/, .idea/, *.iml, .DS_Store)
- README beschreibt Projekt-Setup und Build-Befehle
- Build erfolgreich: `./gradlew build`

**Abhaengigkeiten:** Keine

**Schaetzung:** S (Klein)

**Dateien:**
- `settings.gradle.kts`
- `shared/build.gradle.kts`
- `shared/src/commonMain/kotlin/com/pushup/Hello.kt`
- `shared/src/commonTest/kotlin/com/pushup/HelloTest.kt`
- `README.md`
- `.gitignore`

---

## Task 1A.2: SQLDelight Setup und Datenbank-Schema (Lokal)

**Beschreibung:**
Integriere SQLDelight als lokale Datenbank. Definiere das Schema fuer alle Entities: User (lokal), WorkoutSession, PushUpRecord, TimeCredit, UserSettings. Fokus auf lokale Speicherung, Cloud-Sync kommt spaeter.

**Akzeptanzkriterien:**
- SQLDelight Gradle-Plugin konfiguriert
- Schema-Datei: `shared/src/commonMain/sqldelight/com/pushup/db/Database.sq`
- Tabelle **User**: id (TEXT PK), email (TEXT), displayName (TEXT), createdAt (INTEGER), syncedAt (INTEGER)
- Tabelle **WorkoutSession**: id (TEXT PK), userId (TEXT FK), startedAt (INTEGER), endedAt (INTEGER NULL), pushUpCount (INTEGER), earnedTimeCredits (INTEGER), quality (REAL), syncStatus (TEXT), updatedAt (INTEGER)
- Tabelle **PushUpRecord**: id (TEXT PK), sessionId (TEXT FK), timestamp (INTEGER), durationMs (INTEGER), depthScore (REAL), formScore (REAL)
- Tabelle **TimeCredit**: id (TEXT PK), userId (TEXT FK), totalEarnedSeconds (INTEGER), totalSpentSeconds (INTEGER), lastUpdatedAt (INTEGER), syncStatus (TEXT)
- Tabelle **UserSettings**: id (TEXT PK), userId (TEXT FK), pushUpsPerMinuteCredit (INTEGER DEFAULT 10), qualityMultiplierEnabled (INTEGER DEFAULT 0), dailyCreditCapSeconds (INTEGER NULL)
- Queries fuer jede Tabelle: insert, selectById, selectAll, update, delete
- WorkoutSession: selectByUserId, selectByDateRange, selectUnsyncedSessions
- Build erfolgreich: `./gradlew generateSqlDelightInterface`

**Abhaengigkeiten:** Task 1A.1

**Schaetzung:** M (Mittel)

**Dateien:**
- `shared/src/commonMain/sqldelight/com/pushup/db/Database.sq`
- `shared/build.gradle.kts` (SQLDelight Dependency)

---

## Task 1A.3: Domain Models definieren

**Beschreibung:**
Erstelle alle Kotlin Data Classes im Domain-Layer. Diese Modelle sind plattformunabhaengig und werden von Use-Cases, UI und API genutzt.

**Akzeptanzkriterien:**
- Package: `shared/src/commonMain/kotlin/com/pushup/domain/model/`
- **User**: id, email, displayName, createdAt, lastSyncedAt
- **WorkoutSession**: id, userId, startedAt, endedAt?, pushUpCount, earnedTimeCreditSeconds, quality (Float 0-1), syncStatus (enum: SYNCED, PENDING, FAILED)
- **PushUpRecord**: id, sessionId, timestamp, durationMs, depthScore (Float 0-1), formScore (Float 0-1)
- **TimeCredit**: userId, totalEarnedSeconds, totalSpentSeconds, availableSeconds (berechnet: earned - spent), lastUpdatedAt, syncStatus
- **UserSettings**: userId, pushUpsPerMinuteCredit, qualityMultiplierEnabled, dailyCreditCapSeconds?
- **WorkoutSummary**: session, records (List), earnedCredits
- **DailyStats**: date, totalPushUps, totalSessions, totalEarnedSeconds, averageQuality
- **WeeklyStats**: weekStartDate, totalPushUps, totalSessions, totalEarnedSeconds, dailyBreakdown (List of DailyStats)
- **MonthlyStats**: month, year, totalPushUps, totalSessions, totalEarnedSeconds, weeklyBreakdown (List of WeeklyStats)
- **SyncStatus** enum: SYNCED, PENDING, FAILED
- Alle Modelle sind immutable (val), nutzen kotlinx-datetime (Instant, LocalDate)
- @Serializable Annotation fuer API-Serialisierung

**Abhaengigkeiten:** Task 1A.1

**Schaetzung:** M (Mittel)

**Dateien:**
- `domain/model/User.kt`
- `domain/model/WorkoutSession.kt`
- `domain/model/PushUpRecord.kt`
- `domain/model/TimeCredit.kt`
- `domain/model/UserSettings.kt`
- `domain/model/WorkoutSummary.kt`
- `domain/model/Stats.kt` (DailyStats, WeeklyStats, MonthlyStats)
- `domain/model/SyncStatus.kt`

---

## Task 1A.4: Mapper (DB Entity <-> Domain Model)

**Beschreibung:**
Erstelle Mapper-Funktionen die zwischen SQLDelight-Entities und Domain-Models konvertieren.

**Akzeptanzkriterien:**
- Package: `shared/src/commonMain/kotlin/com/pushup/data/mapper/`
- Extension Functions: `DbUser.toDomain()`, `User.toDbEntity()`
- Extension Functions: `DbWorkoutSession.toDomain()`, `WorkoutSession.toDbEntity()`
- Extension Functions: `DbPushUpRecord.toDomain()`, `PushUpRecord.toDbEntity()`
- Extension Functions: `DbTimeCredit.toDomain()`, `TimeCredit.toDbEntity()`
- Extension Functions: `DbUserSettings.toDomain()`, `UserSettings.toDbEntity()`
- UUID-String <-> UUID Konvertierung
- Timestamp (Long) <-> Instant Konvertierung
- SyncStatus String <-> Enum Konvertierung
- Unit Tests fuer alle Mapper (in commonTest)

**Abhaengigkeiten:** Task 1A.2, Task 1A.3

**Schaetzung:** S (Klein)

**Dateien:**
- `data/mapper/UserMapper.kt`
- `data/mapper/WorkoutMapper.kt`
- `data/mapper/TimeCreditMapper.kt`
- `data/mapper/SettingsMapper.kt`
- `commonTest/kotlin/data/mapper/MapperTest.kt`

---

## Task 1A.5: Repository-Interfaces (Domain-Layer)

**Beschreibung:**
Definiere alle Repository-Interfaces im Domain-Layer. Diese beschreiben WAS die Repositories koennen, ohne WIE (Implementierung kommt spaeter).

**Akzeptanzkriterien:**
- Package: `shared/src/commonMain/kotlin/com/pushup/domain/repository/`
- **UserRepository**: getCurrentUser(), saveUser(user), updateUser(user)
- **WorkoutSessionRepository**: save(session), getById(id), getAllByUserId(userId), getByDateRange(userId, from, to), getUnsyncedSessions(userId), markAsSynced(id), delete(id)
- **PushUpRecordRepository**: save(record), saveAll(records), getBySessionId(sessionId), delete(id)
- **TimeCreditRepository**: get(userId), update(credit), addEarnedSeconds(userId, seconds), addSpentSeconds(userId, seconds), markAsSynced(userId)
- **UserSettingsRepository**: get(userId), update(settings)
- **StatsRepository**: getDailyStats(userId, date), getWeeklyStats(userId, weekStart), getMonthlyStats(userId, month, year), getTotalStats(userId)
- Alle Methoden sind suspend functions
- Return-Typen: Result<T> fuer fehlerbehandlung (oder nullable)

**Abhaengigkeiten:** Task 1A.3

**Schaetzung:** S (Klein)

**Dateien:**
- `domain/repository/UserRepository.kt`
- `domain/repository/WorkoutSessionRepository.kt`
- `domain/repository/PushUpRecordRepository.kt`
- `domain/repository/TimeCreditRepository.kt`
- `domain/repository/UserSettingsRepository.kt`
- `domain/repository/StatsRepository.kt`

---

## Task 1A.6: Repository-Implementierungen (Lokal mit SQLDelight)

**Beschreibung:**
Implementiere alle Repositories mit SQLDelight als lokale Datenquelle. Nutzt die Mapper aus Task 1A.4.

**Akzeptanzkriterien:**
- Package: `shared/src/commonMain/kotlin/com/pushup/data/repository/`
- **UserRepositoryImpl**: Implementiert UserRepository, nutzt SQLDelight User-Queries
- **WorkoutSessionRepositoryImpl**: Implementiert WorkoutSessionRepository, nutzt Queries + Mapper
- **PushUpRecordRepositoryImpl**: Implementiert PushUpRecordRepository
- **TimeCreditRepositoryImpl**: Implementiert TimeCreditRepository
- **UserSettingsRepositoryImpl**: Implementiert UserSettingsRepository
- **StatsRepositoryImpl**: Implementiert StatsRepository, berechnet Stats aus WorkoutSession-Daten (aggregiert)
- Fehlerbehandlung: DB-Exceptions werden in domain-spezifische Errors gewrappt
- Integration Tests mit In-Memory SQLite Driver (in commonTest)

**Abhaengigkeiten:** Task 1A.2, Task 1A.4, Task 1A.5

**Schaetzung:** L (Gross)

**Dateien:**
- `data/repository/UserRepositoryImpl.kt`
- `data/repository/WorkoutSessionRepositoryImpl.kt`
- `data/repository/PushUpRecordRepositoryImpl.kt`
- `data/repository/TimeCreditRepositoryImpl.kt`
- `data/repository/UserSettingsRepositoryImpl.kt`
- `data/repository/StatsRepositoryImpl.kt`
- `commonTest/kotlin/data/repository/RepositoryTests.kt`

---

## Task 1A.7 - 1A.13: Use-Cases (Business-Logik)

**Hinweis:** Diese sind fast identisch zur ersten Version, nur mit User-ID Parameter.

### Task 1A.7: Use-Case -- User Login/Registrierung (Lokal Stub)

**Beschreibung:**
Erstelle einen Stub-Use-Case fuer Login. Vorerst wird nur ein lokaler "Guest"-User erstellt. Wird in Phase 1B durch echte Auth ersetzt.

**Akzeptanzkriterien:**
- **GetOrCreateLocalUserUseCase**: Prueft ob ein lokaler User existiert, wenn nicht erstellt er einen "Guest"-User mit generierter ID
- User wird in der lokalen DB gespeichert
- Gibt den User zurueck
- Unit Tests

**Abhaengigkeiten:** Task 1A.5

**Schaetzung:** S (Klein)

**Dateien:**
- `domain/usecase/GetOrCreateLocalUserUseCase.kt`

---

### Task 1A.8: Use-Case -- Workout starten

**Beschreibung:**
Erstellt eine neue WorkoutSession fuer den aktuellen User.

**Akzeptanzkriterien:**
- **StartWorkoutUseCase**: Parameter userId
- Erstellt WorkoutSession mit: generierte UUID, userId, aktuellem Timestamp, endedAt=null, pushUpCount=0, earnedTimeCredits=0, quality=0.0, syncStatus=PENDING
- Speichert via WorkoutSessionRepository
- Prueft ob bereits laufendes Workout existiert (Exception wenn ja)
- Gibt WorkoutSession zurueck
- Unit Tests

**Abhaengigkeiten:** Task 1A.5

**Schaetzung:** S (Klein)

**Dateien:**
- `domain/usecase/StartWorkoutUseCase.kt`

---

### Task 1A.9: Use-Case -- Push-Up aufzeichnen

**Beschreibung:**
Zeichnet einen einzelnen Push-Up auf und aktualisiert die Session.

**Akzeptanzkriterien:**
- **RecordPushUpUseCase**: Parameter sessionId, durationMs, depthScore, formScore
- Erstellt PushUpRecord und speichert
- Aktualisiert WorkoutSession: pushUpCount +1, quality = laufender Durchschnitt der formScores
- syncStatus bleibt PENDING
- Gibt PushUpRecord zurueck
- Unit Tests

**Abhaengigkeiten:** Task 1A.5

**Schaetzung:** S (Klein)

**Dateien:**
- `domain/usecase/RecordPushUpUseCase.kt`

---

### Task 1A.10: Use-Case -- Workout beenden

**Beschreibung:**
Beendet das Workout und berechnet das verdiente Zeitguthaben.

**Akzeptanzkriterien:**
- **FinishWorkoutUseCase**: Parameter sessionId
- Setzt endedAt auf jetzt
- Berechnet earnedTimeCredits: (pushUpCount / pushUpsPerMinuteCredit) * 60 Sekunden
- Optional: Quality Multiplier anwenden (aus UserSettings)
- Optional: Daily Cap pruefen
- Aktualisiert WorkoutSession in DB
- Aktualisiert TimeCredit: addEarnedSeconds(earnedTimeCredits), syncStatus=PENDING
- Gibt WorkoutSummary zurueck (Session + alle Records + verdiente Credits)
- Unit Tests: Normal, mit Quality Multiplier, mit Daily Cap

**Abhaengigkeiten:** Task 1A.5

**Schaetzung:** M (Mittel)

**Dateien:**
- `domain/usecase/FinishWorkoutUseCase.kt`

---

### Task 1A.11: Use-Case -- Zeitguthaben abfragen

**Beschreibung:**
Liefert aktuellen TimeCredit-Stand.

**Akzeptanzkriterien:**
- **GetTimeCreditUseCase**: Parameter userId
- Gibt TimeCredit zurueck (totalEarned, totalSpent, available)
- Wenn nicht existiert: Erstellt leeren TimeCredit (alles 0)
- Unit Tests

**Abhaengigkeiten:** Task 1A.5

**Schaetzung:** S (Klein)

**Dateien:**
- `domain/usecase/GetTimeCreditUseCase.kt`

---

### Task 1A.12: Use-Case -- Zeitguthaben verbrauchen

**Beschreibung:**
Zieht Sekunden vom Guthaben ab (fuer Screen-Time).

**Akzeptanzkriterien:**
- **SpendTimeCreditUseCase**: Parameter userId, secondsToSpend
- Prueft ob genug Guthaben vorhanden
- Wenn ja: addSpentSeconds(secondsToSpend), syncStatus=PENDING
- Wenn nein: Gibt Error zurueck
- Gibt aktualisiertes TimeCredit zurueck
- Unit Tests

**Abhaengigkeiten:** Task 1A.5

**Schaetzung:** S (Klein)

**Dateien:**
- `domain/usecase/SpendTimeCreditUseCase.kt`

---

### Task 1A.13: Use-Case -- Statistiken abfragen

**Beschreibung:**
Liefert aggregierte Statistiken fuer verschiedene Zeitraeume.

**Akzeptanzkriterien:**
- **GetDailyStatsUseCase**: Parameter userId, date (LocalDate) -> DailyStats
- **GetWeeklyStatsUseCase**: Parameter userId, weekStartDate -> WeeklyStats (inkl. 7 DailyStats)
- **GetMonthlyStatsUseCase**: Parameter userId, month, year -> MonthlyStats (inkl. WeeklyStats)
- **GetTotalStatsUseCase**: Parameter userId -> Gesamt-Statistiken (seit App-Installation)
- Stats beinhalten: totalPushUps, totalSessions, totalEarnedSeconds, averageQuality, averagePushUpsPerSession, bestSession, currentStreak
- Streak-Berechnung: Aufeinanderfolgende Tage mit mind. 1 Workout
- Unit Tests mit Mock-Daten

**Abhaengigkeiten:** Task 1A.5

**Schaetzung:** L (Gross)

**Dateien:**
- `domain/usecase/GetDailyStatsUseCase.kt`
- `domain/usecase/GetWeeklyStatsUseCase.kt`
- `domain/usecase/GetMonthlyStatsUseCase.kt`
- `domain/usecase/GetTotalStatsUseCase.kt`

---

### Task 1A.14: Use-Case -- User-Einstellungen

**Beschreibung:**
Get/Update User-Einstellungen.

**Akzeptanzkriterien:**
- **GetUserSettingsUseCase**: Parameter userId, erstellt Defaults wenn nicht existiert
- **UpdateUserSettingsUseCase**: Parameter UserSettings, validiert Werte, speichert
- Defaults: pushUpsPerMinuteCredit=10, qualityMultiplierEnabled=false, dailyCreditCapSeconds=null
- Unit Tests

**Abhaengigkeiten:** Task 1A.5

**Schaetzung:** S (Klein)

**Dateien:**
- `domain/usecase/GetUserSettingsUseCase.kt`
- `domain/usecase/UpdateUserSettingsUseCase.kt`

---

## Task 1A.15: Dependency Injection Setup (Koin)

**Beschreibung:**
Richte Koin als DI-Framework ein. Alle Repositories und Use-Cases werden verdrahtet.

**Akzeptanzkriterien:**
- Koin Dependency in shared/build.gradle.kts
- Module-Definition: `shared/src/commonMain/kotlin/com/pushup/di/AppModule.kt`
- SQLDelight Driver als expect/actual (iOS: NativeSqliteDriver, Android: AndroidSqliteDriver)
- Alle Repositories als Singletons
- Alle Use-Cases als Factory (neue Instanz pro Aufruf)
- `initKoin()` Funktion die von iOS/Android aufgerufen wird
- Unit Tests koennen Dependencies mocken

**Abhaengigkeiten:** Task 1A.6, Task 1A.7 - 1A.14

**Schaetzung:** M (Mittel)

**Dateien:**
- `di/AppModule.kt`
- `iosMain/kotlin/com/pushup/di/KoinIOS.kt` (expect/actual)
- `androidMain/kotlin/com/pushup/di/KoinAndroid.kt`

---

## Task 1A.16: CI Pipeline (GitHub Actions)

**Beschreibung:**
Erstelle CI Pipeline die bei Push/PR automatisch baut und testet.

**Akzeptanzkriterien:**
- Workflow: `.github/workflows/ci.yml`
- Trigger: Push auf main/develop, alle PRs
- Jobs: Build shared-Modul, Run Tests, Lint
- JDK 17 Setup, Gradle Cache
- `./gradlew build` und `./gradlew allTests`
- Build-Status Badge in README
- Laeuft in unter 10 Min

**Abhaengigkeiten:** Task 1A.1

**Schaetzung:** S (Klein)

**Dateien:**
- `.github/workflows/ci.yml`

---
---

# PHASE 1B: Backend, API, User-Accounts & Cloud-Sync

**Ziel:** Supabase + Ktor Backend steht, User-Accounts funktionieren, Daten werden in die Cloud synchronisiert.

---

## Task 1B.1: Supabase Projekt erstellen und PostgreSQL Schema

**Beschreibung:**
Erstelle ein Supabase-Projekt und definiere das komplette DB-Schema in PostgreSQL. Supabase generiert automatisch REST-APIs dafuer.

**Akzeptanzkriterien:**
- Supabase Projekt angelegt (Free Tier reicht fuer Start)
- PostgreSQL Schema mit folgenden Tabellen:

**Tabelle: users**
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Tabelle: workout_sessions**
```sql
CREATE TABLE workout_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ,
  push_up_count INTEGER DEFAULT 0,
  earned_time_credits INTEGER DEFAULT 0,
  quality REAL DEFAULT 0.0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_workout_sessions_user_id ON workout_sessions(user_id);
CREATE INDEX idx_workout_sessions_started_at ON workout_sessions(started_at DESC);
```

**Tabelle: push_up_records**
```sql
CREATE TABLE push_up_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES workout_sessions(id) ON DELETE CASCADE,
  timestamp TIMESTAMPTZ NOT NULL,
  duration_ms INTEGER,
  depth_score REAL,
  form_score REAL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_push_up_records_session_id ON push_up_records(session_id);
```

**Tabelle: time_credits**
```sql
CREATE TABLE time_credits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
  total_earned_seconds BIGINT DEFAULT 0,
  total_spent_seconds BIGINT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_time_credits_user_id ON time_credits(user_id);
```

**Tabelle: user_settings**
```sql
CREATE TABLE user_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
  push_ups_per_minute_credit INTEGER DEFAULT 10,
  quality_multiplier_enabled BOOLEAN DEFAULT FALSE,
  daily_credit_cap_seconds BIGINT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

- Row Level Security (RLS) aktiviert fuer alle Tabellen
- RLS Policies: User kann nur eigene Daten lesen/schreiben
- Supabase Auto-REST-API ist verfuegbar (`/rest/v1/workout_sessions` etc.)
- Schema-Migration-Datei im Repo: `backend/supabase/migrations/001_initial_schema.sql`

**Abhaengigkeiten:** Keine (kann parallel zu Phase 1A laufen)

**Schaetzung:** M (Mittel)

**Dateien:**
- `backend/supabase/migrations/001_initial_schema.sql`
- `backend/supabase/seed.sql` (optional: Test-Daten)
- `backend/README.md` (Supabase Setup Anleitung)

---

## Task 1B.2: Supabase Auth Setup (Email, Apple, Google)

**Beschreibung:**
Konfiguriere Supabase Auth fuer Email-Login, Apple Sign-In und Google Sign-In.

**Akzeptanzkriterien:**
- Email Auth aktiviert (Email + Passwort, Email Magic Link)
- Apple Sign-In Provider konfiguriert (Client ID, Redirect URL)
- Google Sign-In Provider konfiguriert (Client ID, Secret)
- Auth Callbacks konfiguriert (Deep Links fuer iOS/Android)
- Supabase Auth Policies pruefen dass nur authenticated Users auf Daten zugreifen
- Test: Registrierung via Email funktioniert in Supabase Dashboard

**Abhaengigkeiten:** Task 1B.1

**Schaetzung:** S (Klein)

**Dokumentation:**
- `backend/AUTH_SETUP.md` (Anleitung zur Auth-Konfiguration)

---

## Task 1B.3: Ktor Backend Projekt Setup

**Beschreibung:**
Erstelle ein Ktor Backend-Projekt (Kotlin) fuer Custom-Logik die nicht ueber Supabase Auto-API laeuft (z.B. komplexe Statistik-Aggregationen, Leaderboards).

**Akzeptanzkriterien:**
- Neues Modul: `backend/` (Ktor Projekt)
- Gradle Build: `backend/build.gradle.kts`
- Ktor Dependencies: Server (Netty), Content Negotiation (JSON), CORS, Auth (JWT)
- Basis-Struktur: `Application.kt`, `Routing.kt`, `Plugins.kt`
- Healthcheck Endpoint: `GET /health` -> `{"status": "ok"}`
- JSON Serialization mit kotlinx-serialization
- Dockerfile fuer Deployment
- Lokal lauffaehig: `./gradlew :backend:run` -> Server auf localhost:8080

**Abhaengigkeiten:** Keine (parallel zu Phase 1A/1B)

**Schaetzung:** M (Mittel)

**Dateien:**
- `backend/build.gradle.kts`
- `backend/src/main/kotlin/com/pushup/Application.kt`
- `backend/src/main/kotlin/com/pushup/plugins/Routing.kt`
- `backend/src/main/kotlin/com/pushup/plugins/Serialization.kt`
- `backend/Dockerfile`

---

## Task 1B.4: Ktor <-> Supabase Integration

**Beschreibung:**
Verbinde das Ktor-Backend mit Supabase. Ktor nutzt die Supabase PostgreSQL-Datenbank fuer Queries und validiert Supabase JWT-Tokens.

**Akzeptanzkriterien:**
- Ktor nutzt Exposed (Kotlin SQL Library) fuer DB-Zugriff
- DB Connection Pool zu Supabase PostgreSQL (Connection String aus .env)
- JWT Auth Plugin: Validiert Supabase Access Tokens (HS256, Secret aus Supabase Settings)
- Middleware: Extrahiert User-ID aus JWT und stellt sie fuer Routes bereit
- Test-Route: `GET /api/me` -> Gibt aktuellen User zurueck (aus DB via Exposed)
- Umgebungsvariablen: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_JWT_SECRET`, `DATABASE_URL`
- `.env.example` Datei im Repo

**Abhaengigkeiten:** Task 1B.1, Task 1B.3

**Schaetzung:** M (Mittel)

**Dateien:**
- `backend/src/main/kotlin/com/pushup/plugins/Database.kt`
- `backend/src/main/kotlin/com/pushup/plugins/Auth.kt`
- `backend/src/main/kotlin/com/pushup/routes/UserRoutes.kt`
- `backend/.env.example`

---

## Task 1B.5: Ktor API Endpoints -- Statistiken

**Beschreibung:**
Implementiere Custom-Endpoints fuer aggregierte Statistiken die komplexe SQL-Queries benoetigen (Supabase Auto-API ist hier zu limitiert).

**Akzeptanzkriterien:**
- `GET /api/stats/daily?date=2026-03-02` -> DailyStats (JSON)
- `GET /api/stats/weekly?week_start=2026-02-24` -> WeeklyStats mit 7 DailyStats
- `GET /api/stats/monthly?month=3&year=2026` -> MonthlyStats mit WeeklyStats
- `GET /api/stats/total` -> Gesamt-Statistiken seit App-Installation
- `GET /api/stats/streak` -> Aktueller Streak (aufeinanderfolgende Tage mit Workouts)
- Alle Endpoints authentifiziert (JWT-Token required)
- Endpoints nutzen Exposed fuer DB-Queries (COUNT, SUM, AVG Aggregationen)
- Response-DTOs (Data Transfer Objects) mit @Serializable
- Unit Tests fuer Statistik-Logik

**Abhaengigkeiten:** Task 1B.4

**Schaetzung:** L (Gross)

**Dateien:**
- `backend/src/main/kotlin/com/pushup/routes/StatsRoutes.kt`
- `backend/src/main/kotlin/com/pushup/service/StatsService.kt`
- `backend/src/main/kotlin/com/pushup/dto/StatsDTO.kt`
- `backend/src/test/kotlin/com/pushup/service/StatsServiceTest.kt`

---

## Task 1B.6: Ktor Deployment (Railway/Fly.io/Render)

**Beschreibung:**
Deploye das Ktor-Backend auf einer Hosting-Plattform. Railway empfohlen (einfach, gutes Free-Tier).

**Akzeptanzkriterien:**
- Ktor Backend laeuft auf Railway (oder Fly.io/Render)
- Umgebungsvariablen sind konfiguriert (Supabase Credentials, DB URL)
- Public URL verfuegbar (z.B. `https://pushup-api.railway.app`)
- Health-Check funktioniert: `curl https://pushup-api.railway.app/health`
- Auto-Deploy bei Push auf main-Branch (via Railway GitHub Integration)
- Logging/Monitoring eingerichtet (Railway Dashboard)

**Abhaengigkeiten:** Task 1B.5

**Schaetzung:** S (Klein)

**Dokumentation:**
- `backend/DEPLOYMENT.md` (Deployment-Anleitung)

---

## Task 1B.7: KMP API Client (Ktor Client)

**Beschreibung:**
Erstelle einen API-Client im KMP shared-Modul der mit Supabase und dem Ktor-Backend kommuniziert.

**Akzeptanzkriterien:**
- Ktor Client Dependency in shared/build.gradle.kts
- Package: `shared/src/commonMain/kotlin/com/pushup/data/api/`
- **SupabaseClient**: Wrapper fuer Supabase REST-API (CRUD fuer WorkoutSession, PushUpRecord, TimeCredit)
- **KtorApiClient**: Client fuer Custom Ktor-Endpoints (Stats, etc.)
- Auth-Header mit JWT-Token bei jedem Request
- Request/Response DTOs mit @Serializable
- Fehlerbehandlung: Network Errors, HTTP Errors (401, 404, 500) werden in Domain-Exceptions gemappt
- Retry-Logic fuer transiente Fehler (Timeout, 503)
- Engine: expect/actual (iOS: Darwin, Android: OkHttp)

**Abhaengigkeiten:** Task 1B.1, Task 1B.5

**Schaetzung:** M (Mittel)

**Dateien:**
- `data/api/SupabaseClient.kt`
- `data/api/KtorApiClient.kt`
- `data/api/dto/WorkoutSessionDTO.kt`
- `data/api/dto/StatsDTO.kt`
- `data/api/ApiException.kt`

---

## Task 1B.8: Authentication Use-Cases (KMP)

**Beschreibung:**
Implementiere Auth-Use-Cases im KMP Core: Registrierung, Login, Logout, Token-Refresh.

**Akzeptanzkriterien:**
- **RegisterWithEmailUseCase**: Parameter email, password -> ruft Supabase Auth API, speichert User in lokaler DB
- **LoginWithEmailUseCase**: Parameter email, password -> Supabase Auth, speichert Token lokal (SecureStorage/Keychain)
- **LoginWithAppleUseCase**: Parameter Apple ID Token -> Supabase Auth
- **LoginWithGoogleUseCase**: Parameter Google ID Token -> Supabase Auth
- **LogoutUseCase**: Loescht Token, loescht lokale Daten (optional)
- **GetCurrentUserUseCase**: Gibt aktuell eingeloggten User zurueck (aus lokalem Token oder DB)
- **RefreshTokenUseCase**: Erneuert abgelaufenen Access Token via Refresh Token
- Token Storage: expect/actual (iOS: Keychain, Android: EncryptedSharedPreferences)
- Unit Tests mit Mock Supabase-Client

**Abhaengigkeiten:** Task 1B.2, Task 1B.7

**Schaetzung:** L (Gross)

**Dateien:**
- `domain/usecase/auth/RegisterWithEmailUseCase.kt`
- `domain/usecase/auth/LoginWithEmailUseCase.kt`
- `domain/usecase/auth/LoginWithAppleUseCase.kt`
- `domain/usecase/auth/LogoutUseCase.kt`
- `domain/usecase/auth/GetCurrentUserUseCase.kt`
- `domain/usecase/auth/RefreshTokenUseCase.kt`
- `data/storage/TokenStorage.kt` (expect/actual)

---

## Task 1B.9: Cloud-Sync Use-Cases

**Beschreibung:**
Implementiere automatische Synchronisation zwischen lokaler DB und Supabase. Offline-First: Lokale Daten werden bei Internet-Verbindung hochgeladen.

**Akzeptanzkriterien:**
- **SyncWorkoutsUseCase**: Uploaded alle WorkoutSessions mit syncStatus=PENDING zu Supabase, markiert als SYNCED
- **SyncTimeCreditUseCase**: Synct TimeCredit zu Supabase
- **SyncFromCloudUseCase**: Laed neueste Daten von Supabase runter (z.B. nach Login auf neuem Geraet)
- Konflikt-Behandlung: "Last Write Wins" (updatedAt Timestamp vergleichen)
- Sync laeuft automatisch: Bei App-Start, nach jedem Workout, periodisch im Hintergrund
- Network-Status-Check: Sync nur bei Internet-Verbindung
- Retry bei Fehler (Exponential Backoff)
- Unit Tests mit Mock API-Client

**Abhaengigkeiten:** Task 1B.7, Task 1A.6

**Schaetzung:** L (Gross)

**Dateien:**
- `domain/usecase/sync/SyncWorkoutsUseCase.kt`
- `domain/usecase/sync/SyncTimeCreditUseCase.kt`
- `domain/usecase/sync/SyncFromCloudUseCase.kt`
- `domain/usecase/sync/SyncManager.kt` (orchestriert alle Syncs)

---

## Task 1B.10: Update Repositories fuer Cloud-Sync

**Beschreibung:**
Erweitere die bestehenden Repository-Implementierungen um Cloud-Sync-Logik. Repositories entscheiden ob Daten lokal oder vom Server geladen werden.

**Akzeptanzkriterien:**
- WorkoutSessionRepositoryImpl nutzt SupabaseClient fuer synced Sessions
- Bei save(): Speichert lokal mit syncStatus=PENDING, triggert Sync im Hintergrund
- Bei getAll(): Laed von lokal, merged mit Cloud-Daten wenn verfuegbar
- TimeCreditRepositoryImpl synct bei jeder Aenderung
- StatsRepositoryImpl kann lokal berechnen ODER von Ktor-API laden (schneller bei vielen Daten)
- Cache-Strategy: Lokale Daten sind Source of Truth, Cloud ist Backup/Sync-Target
- Tests: Mock API-Client, teste Online/Offline Szenarien

**Abhaengigkeiten:** Task 1B.9, Task 1A.6

**Schaetzung:** M (Mittel)

**Dateien:**
- Update `data/repository/WorkoutSessionRepositoryImpl.kt`
- Update `data/repository/TimeCreditRepositoryImpl.kt`
- Update `data/repository/StatsRepositoryImpl.kt`

---

## Task 1B.11: Backend CI/CD Pipeline

**Beschreibung:**
Erstelle CI/CD Pipeline fuer das Ktor-Backend: Tests, Build, Docker Image, Deploy.

**Akzeptanzkriterien:**
- Workflow: `.github/workflows/backend-ci.yml`
- Trigger: Push auf main (backend/ Dateien geaendert)
- Jobs: Lint, Test, Build Docker Image, Push zu Registry, Deploy zu Railway
- Umgebungsvariablen als GitHub Secrets
- Rollback-Mechanismus bei fehlerhaftem Deployment

**Abhaengigkeiten:** Task 1B.6

**Schaetzung:** M (Mittel)

**Dateien:**
- `.github/workflows/backend-ci.yml`

---
---

# PHASE 2: Push-Up Erkennung (iOS, Apple Vision Framework)

**Ziel:** Kamera erkennt Push-Ups in Echtzeit, zaehlt, bewertet Qualitaet. Alles in Swift/iOS.

---

## Task 2.1: AVFoundation Kamera-Setup

**Beschreibung:**
Erstelle wiederverwendbare Kamera-Komponente mit AVFoundation.

**Akzeptanzkriterien:**
- AVCaptureSession konfiguriert (Video-Input, 30 FPS)
- Front/Rueck-Kamera umschaltbar
- AVCaptureVideoDataOutput liefert CMSampleBuffer via Delegate
- Kamera-Berechtigung (Info.plist + Runtime)
- SwiftUI View: CameraPreviewView (UIViewRepresentable)
- Fehlerbehandlung: Kamera nicht verfuegbar, Permission denied
- Funktioniert auf iPhone (Simulator hat keine Kamera)

**Abhaengigkeiten:** Keine

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/Camera/CameraManager.swift`
- `iosApp/Camera/CameraPreviewView.swift`
- `Info.plist` (NSCameraUsageDescription)

---

## Task 2.2: Apple Vision Framework -- Body Pose Detection

**Beschreibung:**
Integriere Vision Framework fuer Body Pose Detection.

**Akzeptanzkriterien:**
- VNDetectHumanBodyPoseRequest implementiert
- Pro Frame: Extraktion relevanter Joints (Schultern, Ellbogen, Handgelenke, Hueften, Knie)
- Joint-Koordinaten normalisiert (0-1)
- Confidence-Werte pro Joint
- Datenmodell: BodyPose struct mit allen Joints
- Debug-Overlay: Joints als Punkte/Linien auf Kamerabild
- Performance: <30ms pro Frame

**Abhaengigkeiten:** Task 2.1

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/PoseDetection/VisionPoseDetector.swift`
- `iosApp/PoseDetection/BodyPose.swift`
- `iosApp/PoseDetection/PoseOverlayView.swift`

---

## Task 2.3: Push-Up Erkennungsalgorithmus

**Beschreibung:**
Algorithmus erkennt Push-Up-Zyklus aus Body Poses.

**Akzeptanzkriterien:**
- Ellbogenwinkel-Berechnung aus Schulter-Ellbogen-Handgelenk
- State Machine: IDLE -> DOWN (Winkel <90°) -> UP (Winkel >160°) -> Push-Up gezaehlt
- Hysterese: N aufeinanderfolgende Frames im neuen Zustand
- Cooldown nach Push-Up (verhindert Doppelzaehlung)
- Callback bei Push-Up-Event
- Unit Tests mit Pose-Sequenzen

**Abhaengigkeiten:** Task 2.2

**Schaetzung:** L (Gross)

**Dateien:**
- `iosApp/PoseDetection/PushUpDetector.swift`
- `iosApp/PoseDetection/PushUpStateMachine.swift`
- `iosAppTests/PoseDetection/PushUpDetectorTests.swift`

---

## Task 2.4: Form-Bewertung (Qualitaets-Score)

**Beschreibung:**
Bewertet Push-Up-Qualitaet: Tiefe, Koerperhaltung, Symmetrie.

**Akzeptanzkriterien:**
- depthScore (0-1): Basiert auf min. Ellbogenwinkel (90°=0.5, <60°=1.0)
- formScore (0-1): Ruecken gerade, Symmetrie, kontrollierte Bewegung
- Kombinierter Score: (depth + form) / 2
- Scores pro PushUpRecord gespeichert
- Unit Tests

**Abhaengigkeiten:** Task 2.3

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/PoseDetection/FormScorer.swift`

---

## Task 2.5: Push-Up Tracking Manager (Verbindung zu KMP)

**Beschreibung:**
Verbindet Kamera, Pose Detection, Algorithmus mit KMP Use-Cases.

**Akzeptanzkriterien:**
- PushUpTrackingManager Klasse (Swift)
- Bei Push-Up: RecordPushUpUseCase (KMP) aufrufen
- Published Properties: currentCount, currentFormScore, isTracking, sessionDuration
- Start/Stop Funktionen (startet Kamera + KMP StartWorkoutUseCase)
- Timer fuer Session-Dauer
- Memory Management: Kamera-Ressourcen freigeben bei Stop

**Abhaengigkeiten:** Task 2.4, Phase 1A (Use-Cases)

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/Workout/PushUpTrackingManager.swift`

---

## Task 2.6: Edge-Case Handling & Performance

**Beschreibung:**
Haertung fuer reale Bedingungen: schlechtes Licht, Winkel, aeltere Geraete.

**Akzeptanzkriterien:**
- Funktioniert bei verschiedenen Lichtern (hell, dunkel, Gegenlicht)
- Keine Person erkannt: Hinweis anzeigen
- Mehrere Personen: Groesste tracken
- Schlechter Winkel: Hinweis
- Performance iPhone 12+: 30 FPS
- Performance iPhone 11/SE: min 15 FPS (reduzierte Frequenz ok)
- Batterie-Optimierung: Pose Detection nur jedes 2./3. Frame wenn noetig
- Auto-Stopp bei App in Hintergrund

**Abhaengigkeiten:** Task 2.5

**Schaetzung:** L (Gross)

**Dateien:**
- `iosApp/PoseDetection/EdgeCaseHandler.swift`
- `iosApp/Workout/PerformanceMonitor.swift`

---
---

# PHASE 3: iOS App MVP (SwiftUI)

**Ziel:** Komplette, schoene iOS-App mit allen Screens, Cloud-Sync, Auth.

---

## Task 3.1: iOS Projekt-Setup & KMP Framework-Einbindung

**Beschreibung:**
Xcode-Projekt erstellen, KMP shared-Framework einbinden.

**Akzeptanzkriterien:**
- Xcode-Projekt (iosApp) mit SwiftUI
- KMP shared als XCFramework eingebunden
- import shared funktioniert
- Koin initialisiert von iOS
- App startet auf Simulator + Device
- Build-Prozess: ./gradlew :shared:assembleXCFramework -> Xcode Build
- Min Deployment Target: iOS 16.0

**Abhaengigkeiten:** Phase 1A komplett

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/iosApp.xcodeproj`
- `iosApp/App/PushUpApp.swift`
- `iosApp/App/AppDelegate.swift` (Koin Init)

---

## Task 3.2: Design-System & Theme

**Beschreibung:**
Erstelle ein einheitliches Design-System: Farben, Typography, Spacing, Components.

**Akzeptanzkriterien:**
- Farbpalette definiert (Primary, Secondary, Background, Text, Success, Error)
- Light + Dark Mode Support
- Typography Styles (Title, Headline, Body, Caption)
- Spacing Constants (4pt Grid: 4, 8, 12, 16, 24, 32, 48)
- Wiederverwendbare Components: PrimaryButton, SecondaryButton, Card, StatCard
- SF Symbols fuer Icons
- Konsistentes Erscheinungsbild ueber alle Screens

**Abhaengigkeiten:** Task 3.1

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/Design/Colors.swift`
- `iosApp/Design/Typography.swift`
- `iosApp/Design/Spacing.swift`
- `iosApp/Design/Components/Buttons.swift`
- `iosApp/Design/Components/Cards.swift`

---

## Task 3.3: Navigation & Tab-Struktur

**Beschreibung:**
Grundlegende App-Navigation mit TabView.

**Akzeptanzkriterien:**
- TabView mit 5 Tabs: Dashboard, Workout, Stats, Profile, Settings
- SF Symbol Icons pro Tab
- NavigationStack pro Tab
- Placeholder-Views fuer jeden Screen
- Tab-Auswahl nicht persistent

**Abhaengigkeiten:** Task 3.2

**Schaetzung:** S (Klein)

**Dateien:**
- `iosApp/App/MainTabView.swift`

---

## Task 3.4: Onboarding & Auth Screens

**Beschreibung:**
Onboarding-Flow und Login/Registrierung Screens.

**Akzeptanzkriterien:**
- Onboarding: 3 Slides (Welcome, Kamera erklaeren, Zeitguthaben erklaeren)
- Onboarding wird nur beim ersten Start gezeigt
- Login Screen: Email + Passwort, "Mit Apple anmelden", "Mit Google anmelden"
- Registrierung Screen: Email, Passwort, Display Name
- Passwort-Vergessen Flow
- Input-Validierung (Email-Format, Passwort-Laenge)
- Loading-States bei API-Calls
- Fehler-Handling mit Toast/Alert
- Nach Login: Navigation zu MainTabView
- Design: Schoen, modern, nutzt Design-System aus Task 3.2

**Abhaengigkeiten:** Task 3.2, Task 1B.8 (Auth Use-Cases)

**Schaetzung:** L (Gross)

**Dateien:**
- `iosApp/Features/Onboarding/OnboardingView.swift`
- `iosApp/Features/Auth/LoginView.swift`
- `iosApp/Features/Auth/RegisterView.swift`
- `iosApp/Features/Auth/AuthViewModel.swift`

---

## Task 3.5: Dashboard Screen

**Beschreibung:**
Hauptscreen mit Zeitguthaben, Tages-Stats, Quick-Actions.

**Akzeptanzkriterien:**
- Grosser, prominenter Zeitguthaben-Anzeiger (Stunden:Minuten:Sekunden)
- Kreisfoermiger Progress-Ring oder Visualisierung
- Tages-Statistik Card: Heutige Push-Ups, Sessions, verdiente Zeit
- Wochen-Uebersicht: Kleine Bar-Chart (letzten 7 Tage)
- "Workout starten" Button (navigiert zu Workout-Tab)
- Letzte Session Card: Kurze Zusammenfassung
- Pull-to-Refresh
- Leerer Zustand: "Starte dein erstes Workout!"
- Loading-States
- Daten von KMP Use-Cases: GetTimeCreditUseCase, GetDailyStatsUseCase
- Design: Schoen, uebersichtlich, nutzt StatCards aus Design-System

**Abhaengigkeiten:** Task 3.3, Task 1A.11, Task 1A.13

**Schaetzung:** L (Gross)

**Dateien:**
- `iosApp/Features/Dashboard/DashboardView.swift`
- `iosApp/Features/Dashboard/DashboardViewModel.swift`
- `iosApp/Features/Dashboard/Components/TimeCreditCard.swift`
- `iosApp/Features/Dashboard/Components/DailyStatsCard.swift`
- `iosApp/Features/Dashboard/Components/WeeklyChart.swift`

---

## Task 3.6: Workout Screen (Kamera + Live-Tracking)

**Beschreibung:**
Workout-Screen mit Kamera, Live-Counter, Push-Up-Tracking.

**Akzeptanzkriterien:**
- Kamera-Preview Vollbild (oder grosser Bereich)
- Live Push-Up Counter gross und gut sichtbar
- Aktueller Form-Score (farbcodiert: gruen/gelb/rot)
- Session-Timer
- Pose-Overlay (optional ein/ausschaltbar)
- Start/Pause/Stop Buttons
- Countdown (3, 2, 1) vor Start
- Bestaetigung beim Stoppen
- Kamerawechsel-Button (Front/Rueck)
- Bildschirm bleibt an (isIdleTimerDisabled)
- Haptic Feedback bei jedem Push-Up
- Sound-Effekt bei Push-Up (optional)
- Design: Minimalistisch, Fokus auf Counter und Kamera

**Abhaengigkeiten:** Task 3.3, Phase 2

**Schaetzung:** XL (Sehr Gross)

**Dateien:**
- `iosApp/Features/Workout/WorkoutView.swift`
- `iosApp/Features/Workout/WorkoutViewModel.swift`
- `iosApp/Features/Workout/Components/LiveCounterView.swift`
- `iosApp/Features/Workout/Components/FormScoreIndicator.swift`
- `iosApp/Features/Workout/Components/WorkoutControls.swift`

---

## Task 3.7: Workout-Abschluss Screen

**Beschreibung:**
Screen nach Workout-Ende mit Zusammenfassung.

**Akzeptanzkriterien:**
- Grosse Zahl: Push-Up-Anzahl
- Verdientes Zeitguthaben prominent ("+ 5 Minuten verdient!")
- Session-Dauer
- Durchschnittliche Qualitaet (Sterne oder Score)
- Vergleich zum Durchschnitt ("12% besser als dein Durchschnitt")
- "Zurueck zum Dashboard" Button
- Share-Button (Screenshot, Text fuer Social Media)
- Animationen: Zahlen zaehlen hoch, Confetti bei neuem Rekord
- Design: Celebratory, positive Vibes

**Abhaengigkeiten:** Task 3.6

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/Features/Workout/WorkoutSummaryView.swift`
- `iosApp/Features/Workout/Components/SummaryCard.swift`

---

## Task 3.8: Stats Screen (Detaillierte Statistiken)

**Beschreibung:**
Dedizierter Stats-Screen mit taeglichen, woechentlichen, monatlichen Statistiken.

**Akzeptanzkriterien:**
- Tab-Auswahl: Taeglich, Woechentlich, Monatlich, Gesamt
- **Taeglich**: Kalender-Ansicht, Tap auf Tag -> Detail-Stats, Farb-Coding (Tage mit/ohne Workout)
- **Woechentlich**: Bar-Chart (7 Tage), Summen, Durchschnitte
- **Monatlich**: Line-Chart (Trend ueber Wochen), Summen, Vergleich zu letztem Monat
- **Gesamt**: Total Push-Ups, Total Sessions, Total Zeit verdient, Laengstes Streak, Durchschnitte, Rekorde
- Streak-Anzeige prominent (Feuer-Icon + Tage)
- Export-Funktion: Stats als CSV/PDF
- Pull-to-Refresh
- Loading-States, Error-Handling
- Daten von KMP: GetDailyStatsUseCase, GetWeeklyStatsUseCase, GetMonthlyStatsUseCase
- Design: Daten-lastig aber schoen, Charts/Graphen nutzen Swift Charts

**Abhaengigkeiten:** Task 3.3, Task 1A.13

**Schaetzung:** XL (Sehr Gross)

**Dateien:**
- `iosApp/Features/Stats/StatsView.swift`
- `iosApp/Features/Stats/StatsViewModel.swift`
- `iosApp/Features/Stats/Components/DailyCalendarView.swift`
- `iosApp/Features/Stats/Components/WeeklyChartView.swift`
- `iosApp/Features/Stats/Components/MonthlyChartView.swift`
- `iosApp/Features/Stats/Components/TotalStatsView.swift`

---

## Task 3.9: History Screen (Workout-Historie)

**Beschreibung:**
Liste aller vergangenen Workouts, Detail-Ansicht.

**Akzeptanzkriterien:**
- Liste aller WorkoutSessions, sortiert nach Datum (neuste zuerst)
- Gruppierung nach Tagen (Section Headers)
- Pro Eintrag: Datum, Uhrzeit, Push-Ups, Dauer, verdiente Zeit, Qualitaet (Sterne)
- Tap -> Detail-Ansicht: Alle PushUpRecords, Chart (Form-Score ueber Zeit)
- Swipe-to-Delete mit Bestaetigung
- Filter: Nur letzte Woche, letzter Monat, Alle
- Suche nach Datum
- Leerer Zustand: "Noch keine Workouts"
- Pull-to-Refresh
- Design: Clean, uebersichtlich

**Abhaengigkeiten:** Task 3.3, Task 1A.6

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/Features/History/HistoryView.swift`
- `iosApp/Features/History/HistoryViewModel.swift`
- `iosApp/Features/History/WorkoutDetailView.swift`
- `iosApp/Features/History/Components/WorkoutListItem.swift`

---

## Task 3.10: Profile Screen

**Beschreibung:**
User-Profile mit Avatar, Name, Account-Info.

**Akzeptanzkriterien:**
- Avatar (Upload von Camera/Galerie, wird in Supabase Storage gespeichert)
- Display Name (editierbar)
- Email (nicht editierbar)
- Seit wann registriert
- Account-Statistiken: Total Push-Ups, Total Workouts, Total Zeit verdient
- Achievements-Sektion (Platzhalter fuer spaeter)
- Logout-Button
- Account loeschen (mit Bestaetigung)
- Design: Clean, modern

**Abhaengigkeiten:** Task 3.3, Task 1B.8

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/Features/Profile/ProfileView.swift`
- `iosApp/Features/Profile/ProfileViewModel.swift`
- `iosApp/Features/Profile/Components/AvatarPicker.swift`

---

## Task 3.11: Settings Screen

**Beschreibung:**
Einstellungen: Push-Up-Rate, Benachrichtigungen, Kamera, etc.

**Akzeptanzkriterien:**
- Push-Ups pro Minute Guthaben (Stepper, 1-50, Default 10)
- Quality Multiplier an/aus
- Taegliches Guthaben-Limit (optional, Picker in Minuten)
- Kamera-Praeferenz (Front/Rueck)
- Pose-Overlay an/aus
- Benachrichtigungen an/aus
- Benachrichtigungs-Zeit (Daily Reminder)
- Haptic Feedback an/aus
- Sound-Effekte an/aus
- Dark Mode (System/Light/Dark)
- Info-Sektion: Erklaerung Zeitguthaben-Formel
- App-Version, Build-Nummer
- Links: Datenschutz, AGBs, Support
- Design: Standard iOS Settings-Style

**Abhaengigkeiten:** Task 3.3, Task 1A.14

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/Features/Settings/SettingsView.swift`
- `iosApp/Features/Settings/SettingsViewModel.swift`

---

## Task 3.12: Benachrichtigungen (Local Notifications)

**Beschreibung:**
Lokale Push-Benachrichtigungen fuer Erinnerungen.

**Akzeptanzkriterien:**
- Permission beim ersten Start
- Taegliche Erinnerung: "Zeit fuer Push-Ups!" (konfigurierbare Uhrzeit)
- Streak-Warnung: "Du hast heute noch kein Workout -- Streak in Gefahr!"
- Guthaben-Warnung: "Dein Zeitguthaben ist aufgebraucht"
- Nach Workout: "Workout abgeschlossen! +X Minuten verdient"
- Einstellungen: An/Aus, Uhrzeit
- Nicht senden wenn heute bereits Workout gemacht

**Abhaengigkeiten:** Task 3.11

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/Services/NotificationManager.swift`

---

## Task 3.13: App-Icon, Launch Screen, Polish

**Beschreibung:**
App-Icon, Launch Screen, visuelles Polish.

**Akzeptanzkriterien:**
- App-Icon in allen Groessen (Asset Catalog)
- Launch Screen (App-Logo + Hintergrund)
- App-Name korrekt (Homescreen, Settings)
- Keine Placeholder-Texte mehr
- Alle Screens haben konsistentes Design
- Animationen/Transitions sind smooth
- Loading-States ueberall
- Error-States mit hilfreichen Nachrichten

**Abhaengigkeiten:** Task 3.5 - 3.11

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/Assets.xcassets/AppIcon.appiconset/`
- `iosApp/App/LaunchScreen.storyboard`

---

## Task 3.14: Offline-Modus & Sync-Indicator

**Beschreibung:**
UI zeigt Sync-Status, funktioniert offline, synct bei Internet.

**Akzeptanzkriterien:**
- Network-Status-Monitor (Online/Offline)
- Sync-Indicator in Navigation Bar (spinning icon waehrend Sync)
- Offline-Banner: "Keine Internetverbindung -- Daten werden spaeter synchronisiert"
- Nach Reconnect: Automatischer Sync
- Unsynced-Data-Badge (z.B. "3 Workouts noch nicht synchronisiert")
- Manueller Sync-Button in Settings
- Funktioniert komplett offline (lokale DB)

**Abhaengigkeiten:** Task 1B.9, Task 3.5

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/Services/NetworkMonitor.swift`
- `iosApp/Components/SyncIndicator.swift`

---
---

# PHASE 4: Screen-Time Kontrolle (iOS)

**Ziel:** Guthaben wird bei Social Media/Streaming verbraucht, Apps blockiert wenn leer.

---

## Task 4.1: Screen Time API Recherche & Machbarkeit

**Beschreibung:**
Detaillierte Recherche zu Apple Screen Time API.

**Akzeptanzkriterien:**
- Dokumentation: Family Controls, Managed Settings, Device Activity Frameworks
- Klaerung: Self-imposed Limits moeglich? Oder nur Family/Kinder?
- Klaerung: Entitlements, Apple-Genehmigung noetig?
- Klaerung: Spezifische Apps blockierbar?
- Klaerung: Bypass-Moeglichkeiten?
- Alternativen: VPN, DNS, Focus Mode Integration
- Bewertung: Machbar / Teilweise / Nicht machbar
- Dokument: `backend/SCREEN_TIME_RESEARCH.md`

**Abhaengigkeiten:** Keine (frueh starten!)

**Schaetzung:** M (Mittel)

**Dateien:**
- `docs/SCREEN_TIME_RESEARCH.md`

---

## Task 4.2: Family Controls Entitlement & Setup

**Beschreibung:**
Beantrage Entitlement, konfiguriere Xcode.

**Akzeptanzkriterien:**
- Family Controls Entitlement beantragt (Apple Developer Account)
- Xcode: Family Controls Capability aktiviert
- Device Activity Monitor Extension Target
- Shield Configuration Extension Target
- AuthorizationCenter.shared.requestAuthorization() funktioniert
- Test: Berechtigung erhalten

**Abhaengigkeiten:** Task 4.1, Apple Developer Account

**Schaetzung:** M (Mittel)

---

## Task 4.3: App-Auswahl UI (FamilyActivityPicker)

**Beschreibung:**
UI zum Auswaehlen welche Apps Guthaben verbrauchen.

**Akzeptanzkriterien:**
- FamilyActivityPicker integriert
- Einzelne Apps + Kategorien waehlbar
- Auswahl persistent (UserDefaults/Core Data)
- Vorschlaege: Social Media, Unterhaltung, Spiele
- Settings: Auswahl aenderbar
- FamilyActivitySelection gespeichert

**Abhaengigkeiten:** Task 4.2

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/Features/ScreenTime/AppSelectionView.swift`

---

## Task 4.4: Guthaben-Timer & App-Blockierung

**Beschreibung:**
Kernlogik: Guthaben runter, bei 0 Apps blockieren.

**Akzeptanzkriterien:**
- DeviceActivityMonitor Extension erkennt App-Start
- Timer zaehlt Guthaben runter (SpendTimeCreditUseCase)
- Bei 0: ManagedSettingsStore blockiert Apps (Shield)
- Custom Shield Screen: "Guthaben aufgebraucht -- Push-Ups machen"
- Button: "Workout starten" (oeffnet App)
- Blockierung aufheben bei neuem Guthaben
- Echtzeit-Update
- Edge Case: App Hintergrund (Timer pausiert/laeuft weiter)

**Abhaengigkeiten:** Task 4.3, Task 1A.12

**Schaetzung:** XL (Sehr Gross)

**Dateien:**
- `DeviceActivityMonitorExtension/DeviceActivityMonitor.swift`
- `ShieldConfigurationExtension/ShieldConfiguration.swift`
- `iosApp/Features/ScreenTime/ScreenTimeManager.swift`

---

## Task 4.5: Screen-Time Benachrichtigungen

**Beschreibung:**
Warnungen bevor Guthaben leer.

**Akzeptanzkriterien:**
- 50% Guthaben: "Noch X Minuten"
- 25%: "Nur noch X Minuten"
- 5 Min: "Gleich aufgebraucht!"
- Bei Blockierung: "Apps gesperrt"
- Bei neuem Guthaben: "Workout abgeschlossen! +X Min"
- Schwellwerte konfigurierbar
- An/Aus in Settings

**Abhaengigkeiten:** Task 4.4

**Schaetzung:** S (Klein)

**Dateien:**
- Update `iosApp/Services/NotificationManager.swift`

---

## Task 4.6: Bypass-Schutz & Fairness

**Beschreibung:**
Schutz gegen Umgehen, aber faire Notfall-Regeln.

**Akzeptanzkriterien:**
- Kein einfaches Deaktivieren
- Notfall-Override: 3x langes Druecken -> 5 Min Unlock (max 2x/Tag)
- App deinstalliert: Blockierung bleibt (Extension)
- Permission widerrufen: Hinweis, Blockierung weg
- Zeit-Manipulation-Schutz (Plausibilitaet)
- Guthaben akkumuliert (verfaellt nicht taeglich)

**Abhaengigkeiten:** Task 4.4

**Schaetzung:** M (Mittel)

**Dateien:**
- `iosApp/Features/ScreenTime/BypassProtection.swift`

---
---

# PHASE 5: Erweiterungen (Zukunft)

---

## Task 5.1: Apple Watch App

**Beschreibung:**
watchOS Companion-App.

**Akzeptanzkriterien:**
- watchOS Target
- Zeitguthaben-Anzeige
- Workout starten/stoppen
- Push-Up via Accelerometer/Gyroscope
- WatchConnectivity Sync zu iPhone
- Complications (Zeitguthaben auf Watch-Face)

**Abhaengigkeiten:** Phase 3

**Schaetzung:** XL

---

## Task 5.2: Apple HealthKit Integration

**Beschreibung:**
Workouts in Health-App schreiben.

**Akzeptanzkriterien:**
- HealthKit Permission
- Workouts als HKWorkout schreiben
- Typ: Functional Strength Training
- Kalorien schaetzen
- Optional: Andere Workouts lesen -> Bonus-Guthaben

**Abhaengigkeiten:** Phase 3

**Schaetzung:** M

---

## Task 5.3: Weitere Uebungen (Squats, Sit-Ups, etc.)

**Beschreibung:**
Mehr Uebungen erkennen.

**Akzeptanzkriterien:**
- Abstrakte ExerciseDetector-Klasse
- Squats: Knie-/Hueftwinkel
- Sit-Ups: Oberkoerper-Winkel
- Burpees: Phasen-Sequenz
- Planks: Position + Timer
- Konfigurierbare Guthaben-Rate
- Uebung waehlen im Workout

**Abhaengigkeiten:** Phase 2

**Schaetzung:** XL

---

## Task 5.4: Android App

**Beschreibung:**
Android-Version mit Jetpack Compose.

**Akzeptanzkriterien:**
- androidApp Modul
- Jetpack Compose UI (gleiche Features wie iOS)
- CameraX
- Google ML Kit Pose Detection
- Material 3 Design
- Min SDK: Android 8.0 (API 26)

**Abhaengigkeiten:** Phase 1, Phase 2 (Algorithmus)

**Schaetzung:** XL

---

## Task 5.5: Leaderboards (Backend + UI)

**Beschreibung:**
Woechentliche/Monatliche Ranglisten.

**Akzeptanzkriterien:**
- Backend: Ktor Endpoints fuer Leaderboards (Top 100, Freunde)
- Aggregation: Woechentlich, Monatlich
- Privacy: Opt-In fuer Leaderboard
- UI: Leaderboard-Screen (Rangliste, eigene Position)
- Badges fuer Top 10

**Abhaengigkeiten:** Phase 1B (Backend)

**Schaetzung:** L

---

## Task 5.6: Challenges (Freunde)

**Beschreibung:**
Challenges mit Freunden.

**Akzeptanzkriterien:**
- Freunde hinzufuegen (Code, QR, Kontakte)
- Challenge erstellen: "Wer macht diese Woche mehr Push-Ups?"
- Freunde-Liste
- Challenge-Notifications
- Gewinner-Announcement

**Abhaengigkeiten:** Phase 1B (Backend), Leaderboards

**Schaetzung:** XL

---

## Task 5.7: Gamification (Achievements, Levels)

**Beschreibung:**
Achievements, Streaks, Levels, XP.

**Akzeptanzkriterien:**
- Achievement-System: "Erster Push-Up", "100 Push-Ups", "7-Tage-Streak", etc.
- Streak-Tracker
- Level-System: XP fuer Push-Ups, Level-Up
- Taegliche Challenge: "Mach 50 Push-Ups heute"
- Animationen bei Achievements
- Achievement-Galerie

**Abhaengigkeiten:** Phase 3

**Schaetzung:** L

---

## Task 5.8: Home Screen Widget (iOS)

**Beschreibung:**
iOS Widget fuer Zeitguthaben.

**Akzeptanzkriterien:**
- WidgetKit Extension
- Small Widget: Zeitguthaben
- Medium: Zeitguthaben + heutige Push-Ups + Streak
- Large: Zeitguthaben + Wochen-Chart
- Timeline Provider
- Tap -> App (Deep Link)
- Lock Screen Widget (iOS 16+)

**Abhaengigkeiten:** Phase 3

**Schaetzung:** M

---

## Task 5.9: In-App Purchases (Premium Features)

**Beschreibung:**
Premium-Abo fuer erweiterte Features.

**Akzeptanzkriterien:**
- StoreKit 2 Integration
- Premium-Features: Unlimitiertes Guthaben, erweiterte Stats, keine Werbung (falls Ads kommen)
- Subscription: Monatlich/Jaehrlich
- Paywall-Screen
- Restore Purchases
- Receipt Validation (Backend)

**Abhaengigkeiten:** Phase 3, Backend

**Schaetzung:** L

---
---

# Groessen-Legende

| Groesse | Zeitrahmen |
|---------|------------|
| S | 2-4 Stunden |
| M | 0.5-1.5 Tage |
| L | 2-4 Tage |
| XL | 1-2 Wochen |

---

# Empfohlene Reihenfolge

```
Phase 1A: 1A.1 -> 1A.2 + 1A.3 (parallel) -> 1A.4 -> 1A.5 -> 1A.6 -> 1A.7-1A.14 -> 1A.15 -> 1A.16

Phase 1B: 1B.1 + 1B.2 + 1B.3 (parallel, frueh starten!) -> 1B.4 -> 1B.5 -> 1B.6 -> 1B.7 -> 1B.8 -> 1B.9 -> 1B.10 -> 1B.11

Phase 2: 2.1 -> 2.2 -> 2.3 -> 2.4 -> 2.5 -> 2.6

Phase 3: 3.1 -> 3.2 -> 3.3 -> 3.4 -> 3.5 + 3.8 + 3.9 + 3.10 + 3.11 (parallel) -> 3.6 -> 3.7 -> 3.12 -> 3.13 -> 3.14

Phase 4: 4.1 (FRUEH starten, parallel zu Phase 1!) -> 4.2 -> 4.3 -> 4.4 -> 4.5 + 4.6

Phase 5: Unabhaengig priorisierbar
```

---

# GESAMT: 60+ Tasks

- **Phase 1A:** 16 Tasks (KMP Core, lokale DB, Use-Cases)
- **Phase 1B:** 11 Tasks (Backend, API, Auth, Cloud-Sync)
- **Phase 2:** 6 Tasks (Push-Up Erkennung)
- **Phase 3:** 14 Tasks (iOS App MVP)
- **Phase 4:** 6 Tasks (Screen-Time)
- **Phase 5:** 9 Tasks (Erweiterungen)

**Total: 62 Tasks**
