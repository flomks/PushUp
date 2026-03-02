# PushUp App -- Detaillierte Task-Liste

Jeder Task ist so formuliert, dass er direkt als Ticket / Trial uebernommen werden kann.
Format pro Task: Titel, Beschreibung, Akzeptanzkriterien, Abhaengigkeiten, Schaetzung.

---
---

## PHASE 1: Projekt-Setup & Core-Logik

**Ziel:** Das KMP-Grundgeruest steht, die gesamte Business-Logik ist implementiert und getestet. Kein Apple Developer Account noetig. Alles laeuft headless (ohne UI).

---

### Task 1.1: KMP Projekt-Grundgeruest aufsetzen

**Beschreibung:**
Erstelle das Kotlin Multiplatform Projekt mit Gradle als Build-System. Das Projekt soll ein shared-Modul enthalten, das spaeter sowohl von der iOS-App als auch von der Android-App genutzt wird. Richte die grundlegende Ordnerstruktur ein (commonMain, commonTest, iosMain, androidMain). Konfiguriere die Kotlin-Version, das KMP-Plugin und die grundlegenden Dependencies (Coroutines, DateTime).

**Akzeptanzkriterien:**
- Gradle-Projekt baut erfolgreich durch (./gradlew build)
- shared-Modul ist angelegt mit commonMain, commonTest, iosMain, androidMain Source-Sets
- Kotlin Coroutines und kotlinx-datetime sind als Dependencies eingebunden
- Eine einfache "Hello World"-Funktion in commonMain ist von commonTest aus testbar
- .gitignore ist konfiguriert (build-Ordner, .gradle, .idea, etc.)
- README im Repo beschreibt wie man das Projekt baut

**Abhaengigkeiten:** Keine (erster Task)

**Schaetzung:** S (Klein)

---

### Task 1.2: SQLDelight einrichten und Datenbank-Schema definieren

**Beschreibung:**
Integriere SQLDelight in das KMP-Projekt als lokale Datenbank-Loesung. Erstelle das komplette Datenbank-Schema mit allen Tabellen: WorkoutSession, PushUpRecord, TimeCredit und UserSettings. Definiere die grundlegenden SQL-Queries (CRUD-Operationen) fuer jede Tabelle.

**Akzeptanzkriterien:**
- SQLDelight Gradle-Plugin ist konfiguriert und generiert Kotlin-Code
- Tabelle "WorkoutSession" mit Feldern: id (TEXT/UUID), startedAt (INTEGER/Timestamp), endedAt (INTEGER/Timestamp nullable), pushUpCount (INTEGER), earnedTimeCredits (INTEGER/Sekunden), quality (REAL/Float)
- Tabelle "PushUpRecord" mit Feldern: id (TEXT/UUID), sessionId (TEXT/FK), timestamp (INTEGER), durationMs (INTEGER), depthScore (REAL), formScore (REAL)
- Tabelle "TimeCredit" mit Feldern: id (TEXT/UUID), totalEarnedSeconds (INTEGER), totalSpentSeconds (INTEGER), lastUpdatedAt (INTEGER)
- Tabelle "UserSettings" mit Feldern: id (TEXT), pushUpsPerMinuteCredit (INTEGER, default 10), qualityMultiplierEnabled (INTEGER/Boolean), dailyCreditCapSeconds (INTEGER nullable)
- Fuer jede Tabelle existieren Queries: insert, selectById, selectAll, update, delete
- Fuer WorkoutSession zusaetzlich: selectByDateRange, selectLatest
- Fuer PushUpRecord zusaetzlich: selectBySessionId
- Schema laesst sich kompilieren (./gradlew generateSqlDelightInterface)

**Abhaengigkeiten:** Task 1.1

**Schaetzung:** M (Mittel)

---

### Task 1.3: Datenmodelle (Domain Models) definieren

**Beschreibung:**
Erstelle die Kotlin-Datenklassen im Domain-Layer (commonMain/domain/model/). Diese Modelle sind unabhaengig von der Datenbank und repraesentieren die Business-Objekte der App. Sie werden in Use-Cases und von der UI verwendet.

**Akzeptanzkriterien:**
- Data class "WorkoutSession" in domain/model/ mit: id, startedAt, endedAt, pushUpCount, earnedTimeCreditSeconds, quality
- Data class "PushUpRecord" in domain/model/ mit: id, sessionId, timestamp, durationMs, depthScore, formScore
- Data class "TimeCredit" in domain/model/ mit: totalEarnedSeconds, totalSpentSeconds, availableSeconds (berechnet)
- Data class "UserSettings" in domain/model/ mit: pushUpsPerMinuteCredit, qualityMultiplierEnabled, dailyCreditCapSeconds
- Data class "WorkoutSummary" in domain/model/ mit: session, records (Liste), earnedCredits
- Alle Modelle nutzen kotlinx-datetime fuer Zeitstempel (Instant)
- Alle Modelle sind immutable (val, nicht var)

**Abhaengigkeiten:** Task 1.1

**Schaetzung:** S (Klein)

---

### Task 1.4: Mapper zwischen Domain-Models und DB-Entities

**Beschreibung:**
Erstelle Mapper-Funktionen die zwischen den SQLDelight-generierten Entities und den Domain-Models konvertieren. Diese Trennung stellt sicher, dass die Domain-Logik unabhaengig von der Datenbank-Implementierung bleibt.

**Akzeptanzkriterien:**
- Mapper-Funktionen (Extension Functions oder eigene Klasse) fuer jede Entity <-> Domain-Model Konvertierung
- WorkoutSession: toDomain() und toEntity()
- PushUpRecord: toDomain() und toEntity()
- TimeCredit: toDomain() und toEntity()
- UserSettings: toDomain() und toEntity()
- UUID-Generierung ist abstrahiert (expect/actual fuer iOS/Android)
- Timestamp-Konvertierung (Long <-> Instant) funktioniert korrekt
- Unit Tests fuer alle Mapper-Funktionen

**Abhaengigkeiten:** Task 1.2, Task 1.3

**Schaetzung:** S (Klein)

---

### Task 1.5: Repository-Interfaces definieren (Domain-Layer)

**Beschreibung:**
Definiere die Repository-Interfaces im Domain-Layer. Diese Interfaces beschreiben WAS die Datenzugriffsschicht kann, ohne zu sagen WIE (Implementierung kommt in Task 1.6). Alle Use-Cases arbeiten nur gegen diese Interfaces.

**Akzeptanzkriterien:**
- Interface "WorkoutSessionRepository" mit: save(session), getById(id), getAll(), getByDateRange(from, to), getLatest(limit), delete(id)
- Interface "PushUpRecordRepository" mit: save(record), saveAll(records), getBySessionId(sessionId), delete(id)
- Interface "TimeCreditRepository" mit: get(), update(credit), addEarnedSeconds(seconds), addSpentSeconds(seconds)
- Interface "UserSettingsRepository" mit: get(), update(settings)
- Alle Methoden sind suspend functions (Coroutines)
- Alle Methoden geben Domain-Models zurueck (nicht DB-Entities)
- Interfaces liegen in domain/repository/

**Abhaengigkeiten:** Task 1.3

**Schaetzung:** S (Klein)

---

### Task 1.6: Repository-Implementierungen (Data-Layer)

**Beschreibung:**
Implementiere die Repository-Interfaces aus Task 1.5 mit SQLDelight als Datenquelle. Die Implementierungen liegen im Data-Layer und nutzen die Mapper aus Task 1.4 zur Konvertierung.

**Akzeptanzkriterien:**
- Klasse "WorkoutSessionRepositoryImpl" implementiert WorkoutSessionRepository
- Klasse "PushUpRecordRepositoryImpl" implementiert PushUpRecordRepository
- Klasse "TimeCreditRepositoryImpl" implementiert TimeCreditRepository
- Klasse "UserSettingsRepositoryImpl" implementiert UserSettingsRepository
- Alle Implementierungen nutzen den SQLDelight-Driver und die generierten Queries
- Alle Implementierungen nutzen die Mapper fuer Domain <-> Entity Konvertierung
- Implementierungen liegen in data/repository/
- Fehlerbehandlung: DB-Fehler werden sauber in Domain-Exceptions gewrappt
- Integration Tests: Jedes Repository wird mit einer In-Memory-DB getestet

**Abhaengigkeiten:** Task 1.2, Task 1.4, Task 1.5

**Schaetzung:** M (Mittel)

---

### Task 1.7: Use-Case -- Workout starten

**Beschreibung:**
Implementiere den Use-Case "StartWorkoutUseCase". Dieser erstellt eine neue WorkoutSession mit Startzeitpunkt und speichert sie in der Datenbank. Er gibt die erstellte Session zurueck, damit die UI die Session-ID fuer das laufende Workout hat.

**Akzeptanzkriterien:**
- Klasse "StartWorkoutUseCase" in domain/usecase/
- Nimmt keine Parameter entgegen (Startzeit wird automatisch gesetzt)
- Erstellt eine neue WorkoutSession mit: generierter UUID, aktuellem Timestamp als startedAt, endedAt=null, pushUpCount=0, earnedTimeCredits=0, quality=0.0
- Speichert die Session ueber das WorkoutSessionRepository
- Gibt die erstellte WorkoutSession zurueck
- Prueft ob bereits ein laufendes Workout existiert (endedAt == null) und wirft ggf. eine Exception
- Unit Tests: Erfolgreich starten, bereits laufendes Workout abfangen

**Abhaengigkeiten:** Task 1.5

**Schaetzung:** S (Klein)

---

### Task 1.8: Use-Case -- Push-Up aufzeichnen

**Beschreibung:**
Implementiere den Use-Case "RecordPushUpUseCase". Dieser wird aufgerufen wenn die Kamera (oder spaeter die Watch) einen einzelnen Push-Up erkennt. Er speichert den einzelnen Push-Up-Record und aktualisiert den Counter der laufenden Session.

**Akzeptanzkriterien:**
- Klasse "RecordPushUpUseCase" in domain/usecase/
- Parameter: sessionId, durationMs, depthScore (Float 0-1), formScore (Float 0-1)
- Erstellt einen neuen PushUpRecord und speichert ihn
- Aktualisiert pushUpCount der zugehoerigen WorkoutSession (+1)
- Aktualisiert quality der Session (laufender Durchschnitt der formScores)
- Prueft ob die Session existiert und noch laeuft (endedAt == null)
- Gibt den aktualisierten PushUpRecord zurueck
- Unit Tests: Push-Up aufzeichnen, Session nicht gefunden, Session bereits beendet

**Abhaengigkeiten:** Task 1.5

**Schaetzung:** S (Klein)

---

### Task 1.9: Use-Case -- Workout beenden und Zeitguthaben berechnen

**Beschreibung:**
Implementiere den Use-Case "FinishWorkoutUseCase". Dieser beendet ein laufendes Workout, berechnet das verdiente Zeitguthaben basierend auf der Anzahl Push-Ups und den Benutzereinstellungen, und aktualisiert das Gesamtguthaben.

**Akzeptanzkriterien:**
- Klasse "FinishWorkoutUseCase" in domain/usecase/
- Parameter: sessionId
- Setzt endedAt auf den aktuellen Timestamp
- Berechnet earnedTimeCredits nach Formel: pushUpCount / pushUpsPerMinuteCredit * 60 (in Sekunden)
- Wenn qualityMultiplier aktiviert: Multipliziert mit quality-abhaengigem Faktor (>0.8 = 1.5x, 0.5-0.8 = 1.0x, <0.5 = 0.7x)
- Wenn dailyCreditCap gesetzt: Prueft ob Tageslimit erreicht und begrenzt ggf.
- Aktualisiert die WorkoutSession in der DB
- Addiert die verdienten Sekunden zum TimeCredit (totalEarnedSeconds)
- Gibt ein WorkoutSummary zurueck (Session + Records + verdiente Credits)
- Unit Tests: Normales Beenden, mit Quality Multiplier, mit Daily Cap, Session nicht gefunden, Session bereits beendet

**Abhaengigkeiten:** Task 1.5

**Schaetzung:** M (Mittel)

---

### Task 1.10: Use-Case -- Zeitguthaben abfragen

**Beschreibung:**
Implementiere den Use-Case "GetTimeCreditUseCase". Dieser liefert den aktuellen Stand des Zeitguthabens: Wie viel wurde verdient, wie viel verbraucht, wie viel ist noch verfuegbar.

**Akzeptanzkriterien:**
- Klasse "GetTimeCreditUseCase" in domain/usecase/
- Keine Parameter
- Gibt ein TimeCredit-Objekt zurueck mit totalEarnedSeconds, totalSpentSeconds, availableSeconds
- availableSeconds = totalEarnedSeconds - totalSpentSeconds (nie negativ, Minimum 0)
- Wenn noch kein TimeCredit existiert: Erstellt einen leeren (alles 0) und gibt ihn zurueck
- Unit Tests: Guthaben vorhanden, kein Guthaben, Guthaben komplett verbraucht

**Abhaengigkeiten:** Task 1.5

**Schaetzung:** S (Klein)

---

### Task 1.11: Use-Case -- Zeitguthaben verbrauchen

**Beschreibung:**
Implementiere den Use-Case "SpendTimeCreditUseCase". Dieser wird spaeter von der Screen-Time-Kontrolle aufgerufen um Guthaben abzuziehen. Vorerst wird er manuell ausgeloest (z.B. Timer in der App).

**Akzeptanzkriterien:**
- Klasse "SpendTimeCreditUseCase" in domain/usecase/
- Parameter: secondsToSpend (Long)
- Prueft ob genug Guthaben vorhanden ist
- Zieht die Sekunden vom availableSeconds ab (erhoet totalSpentSeconds)
- Gibt das aktualisierte TimeCredit-Objekt zurueck
- Wenn nicht genug Guthaben: Gibt einen Fehler/Result zurueck (kein Crash)
- Unit Tests: Erfolgreich verbrauchen, nicht genug Guthaben, exakt aufbrauchen

**Abhaengigkeiten:** Task 1.5

**Schaetzung:** S (Klein)

---

### Task 1.12: Use-Case -- Workout-Statistiken abfragen

**Beschreibung:**
Implementiere den Use-Case "GetWorkoutStatsUseCase". Dieser liefert aggregierte Statistiken ueber die Workouts: Heutige Push-Ups, Wochen-Summe, Gesamt-Summe, laengstes Streak, Durchschnitt pro Session.

**Akzeptanzkriterien:**
- Klasse "GetWorkoutStatsUseCase" in domain/usecase/
- Gibt ein "WorkoutStats" Data-Objekt zurueck mit:
  - todayPushUps: Int (Summe aller Push-Ups heute)
  - todaySessions: Int (Anzahl Sessions heute)
  - weekPushUps: Int (Summe letzte 7 Tage)
  - totalPushUps: Int (Gesamt seit App-Installation)
  - totalSessions: Int
  - averagePushUpsPerSession: Float
  - bestSession: Int (meiste Push-Ups in einer Session)
  - currentStreak: Int (aufeinanderfolgende Tage mit min. 1 Workout)
- Data class "WorkoutStats" in domain/model/
- Unit Tests: Leere Statistiken, einzelne Session, mehrere Tage, Streak-Berechnung

**Abhaengigkeiten:** Task 1.5

**Schaetzung:** M (Mittel)

---

### Task 1.13: Use-Case -- Benutzereinstellungen verwalten

**Beschreibung:**
Implementiere die Use-Cases "GetUserSettingsUseCase" und "UpdateUserSettingsUseCase". Diese ermoeglichen das Lesen und Aendern der Benutzereinstellungen (Push-Up-Rate, Quality Multiplier, Daily Cap).

**Akzeptanzkriterien:**
- Klasse "GetUserSettingsUseCase": Gibt aktuelle UserSettings zurueck, erstellt Default-Einstellungen wenn noch keine existieren
- Klasse "UpdateUserSettingsUseCase": Parameter ist ein UserSettings-Objekt, validiert die Werte (pushUpsPerMinuteCredit muss > 0 sein, dailyCreditCap wenn gesetzt muss > 0 sein), speichert die Einstellungen
- Default-Werte: pushUpsPerMinuteCredit=10, qualityMultiplierEnabled=false, dailyCreditCapSeconds=null
- Unit Tests: Defaults laden, Einstellungen aendern, ungueltige Werte abfangen

**Abhaengigkeiten:** Task 1.5

**Schaetzung:** S (Klein)

---

### Task 1.14: Dependency Injection / Service Locator Setup

**Beschreibung:**
Richte eine einfache Dependency Injection (oder Service Locator Pattern) ein, damit die Use-Cases, Repositories und der Datenbank-Driver sauber verdrahtet werden. Fuer KMP eignet sich Koin gut, alternativ ein manueller Service Locator.

**Akzeptanzkriterien:**
- DI-Framework (Koin empfohlen) oder manueller Service Locator ist eingerichtet
- Alle Repositories sind als Singletons registriert
- Alle Use-Cases sind registriert (koennen pro Aufruf neu erstellt werden)
- SQLDelight DatabaseDriver wird plattformspezifisch erstellt (expect/actual)
- iOS: NativeSqliteDriver, Android: AndroidSqliteDriver
- Eine zentrale "initKoin()" oder "AppModule" Funktion die alles verdrahtet
- Unit Tests koennen die Dependencies einfach mocken/ersetzen

**Abhaengigkeiten:** Task 1.6, Task 1.7 - 1.13

**Schaetzung:** M (Mittel)

---

### Task 1.15: CI Pipeline (GitHub Actions)

**Beschreibung:**
Erstelle eine GitHub Actions CI Pipeline die bei jedem Push und Pull Request automatisch baut und testet. Die Pipeline soll das KMP shared-Modul bauen und alle Unit Tests ausfuehren.

**Akzeptanzkriterien:**
- GitHub Actions Workflow-Datei (.github/workflows/ci.yml)
- Trigger: Push auf main und develop, alle Pull Requests
- Steps: Checkout, JDK Setup (17), Gradle Cache, Build, Test
- ./gradlew build laeuft erfolgreich durch
- ./gradlew allTests laeuft erfolgreich durch
- Build-Status Badge in README.md
- Workflow laeuft in unter 10 Minuten durch

**Abhaengigkeiten:** Task 1.1 (kann parallel zu anderen Tasks erstellt werden)

**Schaetzung:** S (Klein)

---
---

## PHASE 2: Push-Up Erkennung (iOS, Swift)

**Ziel:** Die Kamera erkennt Push-Ups zuverlaessig in Echtzeit, zaehlt sie und bewertet die Ausfuehrungsqualitaet. Alles in Swift/iOS, nutzt Apple Vision Framework.

---

### Task 2.1: Kamera-Setup mit AVFoundation

**Beschreibung:**
Erstelle eine wiederverwendbare Kamera-Komponente mit AVFoundation. Die Kamera soll ein Live-Video-Feed liefern, dessen einzelne Frames an die Pose-Detection weitergegeben werden koennen. Unterstuetzung fuer Front- und Rueckkamera.

**Akzeptanzkriterien:**
- AVCaptureSession ist konfiguriert mit Video-Input
- Unterstuetzung fuer Frontkamera und Rueckkamera (umschaltbar)
- AVCaptureVideoDataOutput liefert CMSampleBuffer-Frames via Delegate
- Kamera-Berechtigung wird korrekt angefragt (Info.plist + Runtime-Permission)
- Kamera-Preview ist als SwiftUI View verfuegbar (UIViewRepresentable)
- Performance: Mindestens 30 FPS Kamera-Feed
- Fehlerbehandlung: Kamera nicht verfuegbar, Berechtigung verweigert
- Funktioniert auf physischem Geraet (Simulator hat keine Kamera)

**Abhaengigkeiten:** Keine (kann parallel zu Phase 1 gestartet werden, braucht aber spaeter Phase 1 fuer die Integration)

**Schaetzung:** M (Mittel)

---

### Task 2.2: Apple Vision Framework -- Body Pose Detection

**Beschreibung:**
Integriere das Apple Vision Framework fuer Body Pose Detection. Die CMSampleBuffer-Frames von der Kamera werden an Vision uebergeben, das die Koerperpunkte (Joints) erkennt und zurueckgibt. Fokus auf die fuer Push-Ups relevanten Punkte: Schultern, Ellbogen, Handgelenke, Hueften.

**Akzeptanzkriterien:**
- VNDetectHumanBodyPoseRequest ist implementiert
- Pro Frame werden die relevanten Body Joints extrahiert: leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist, leftHip, rightHip
- Joint-Positionen werden in normalisierte Koordinaten (0-1) konvertiert
- Confidence-Werte pro Joint sind verfuegbar
- Joints mit zu niedriger Confidence (<0.3) werden als "nicht erkannt" markiert
- Ein Datenmodell "BodyPose" haelt alle erkannten Joints mit Position + Confidence
- Debug-Overlay: Erkannte Joints koennen als Punkte ueber das Kamerabild gezeichnet werden
- Performance: Pose Detection laeuft in unter 30ms pro Frame

**Abhaengigkeiten:** Task 2.1

**Schaetzung:** M (Mittel)

---

### Task 2.3: Push-Up Erkennungsalgorithmus

**Beschreibung:**
Implementiere den Algorithmus der aus den erkannten Body Poses einen Push-Up-Zyklus erkennt. Ein Push-Up besteht aus: Ausgangsposition (Arme gestreckt) -> Runter (Arme gebeugt, Ellbogenwinkel < Schwellwert) -> Hoch (Arme wieder gestreckt). Der Algorithmus muss rauschresistent sein und Fehlzaehlungen vermeiden.

**Akzeptanzkriterien:**
- Berechnung des Ellbogenwinkels aus Schulter-, Ellbogen- und Handgelenkpositionen
- State Machine mit Zustaenden: IDLE -> DOWN -> UP -> (Push-Up gezaehlt) -> IDLE
- Schwellwerte: DOWN wenn Ellbogenwinkel < 90 Grad, UP wenn > 160 Grad (konfigurierbar)
- Hysterese: Zustandswechsel erst nach N aufeinanderfolgenden Frames im neuen Zustand (verhindert Flackern)
- Ein Push-Up wird erst gezaehlt wenn der volle Zyklus DOWN -> UP abgeschlossen ist
- Cooldown nach einem gezaehlten Push-Up (verhindert Doppelzaehlung)
- Callback/Event wenn ein Push-Up erkannt wurde (fuer Counter-Update)
- Unit Tests mit vordefinierten Pose-Sequenzen: Normaler Push-Up, halber Push-Up (nicht zaehlen), schnelle Push-Ups, langsame Push-Ups

**Abhaengigkeiten:** Task 2.2

**Schaetzung:** L (Gross)

---

### Task 2.4: Form-Bewertung (Qualitaets-Score)

**Beschreibung:**
Implementiere die Bewertung der Push-Up-Ausfuehrungsqualitaet. Jeder einzelne Push-Up erhaelt einen depthScore (wie tief) und einen formScore (Koerperposition). Dies fliesst spaeter in den Quality Multiplier beim Zeitguthaben ein.

**Akzeptanzkriterien:**
- depthScore (0.0 - 1.0): Basiert auf dem minimalen Ellbogenwinkel waehrend der DOWN-Phase. Kleiner Winkel = tiefer = hoeher Score. 90 Grad = 0.5, 70 Grad = 0.8, <60 Grad = 1.0
- formScore (0.0 - 1.0): Bewertet die Koerperposition waehrend des Push-Ups:
  - Ruecken gerade (Schulter-Huefte-Linie)?
  - Symmetrie (linker/rechter Arm aehnlich)?
  - Kontrollierte Bewegung (keine ruckartigen Spruenge)?
- Kombierter Score pro Push-Up: (depthScore + formScore) / 2
- Scores werden pro PushUpRecord gespeichert
- Unit Tests mit verschiedenen Pose-Qualitaeten

**Abhaengigkeiten:** Task 2.3

**Schaetzung:** M (Mittel)

---

### Task 2.5: Echtzeit-Counter und Session-Management (iOS-Seite)

**Beschreibung:**
Verbinde die Push-Up-Erkennung mit dem KMP Core. Wenn ein Push-Up erkannt wird, soll der RecordPushUpUseCase aufgerufen werden. Implementiere einen Echtzeit-Counter der die aktuelle Anzahl und den laufenden Score anzeigt.

**Akzeptanzkriterien:**
- PushUpTrackingManager Klasse (Swift) die Kamera, Pose Detection und Algorithmus verbindet
- Bei jedem erkannten Push-Up wird RecordPushUpUseCase aus dem KMP Core aufgerufen
- Published Properties fuer SwiftUI: currentCount, currentFormScore, isTracking, sessionDuration
- Start/Stop Funktionalitaet (startet/beendet Kamera + KMP Workout Session)
- Timer fuer Session-Dauer
- Debounce/Throttle: Core-Updates nicht bei jedem Frame, sondern nur bei Push-Up-Events
- Memory Management: Kamera-Ressourcen werden bei Stop korrekt freigegeben

**Abhaengigkeiten:** Task 2.3, Task 2.4, Phase 1 (KMP Core)

**Schaetzung:** M (Mittel)

---

### Task 2.6: Edge-Case Handling und Performance-Optimierung

**Beschreibung:**
Haerte die Push-Up-Erkennung fuer reale Bedingungen: schlechte Beleuchtung, ungünstige Kamerawinkel, mehrere Personen im Bild, aeltere Geraete. Implementiere Fallbacks und User-Feedback wenn die Erkennung nicht funktioniert.

**Akzeptanzkriterien:**
- Erkennung funktioniert bei verschiedenen Beleuchtungen (Test: hell, dunkel, Gegenlicht)
- Wenn keine Person erkannt wird: User-Hinweis ("Bitte positioniere dich im Kamerabild")
- Wenn mehrere Personen: Nur die dominanteste/groesste Person tracken
- Kamerawinkel-Hinweis wenn Pose nicht gut erkennbar ("Bitte Handy weiter weg stellen")
- Performance auf iPhone 12 und neuer: Stabil 30 FPS
- Performance auf iPhone 11 / SE: Mindestens 15 FPS, ggf. reduzierte Frequenz der Pose Detection
- Batterie-Optimierung: Pose Detection nur bei jedem 2. oder 3. Frame wenn noetig
- Automatischer Stopp wenn App in den Hintergrund geht

**Abhaengigkeiten:** Task 2.5

**Schaetzung:** L (Gross)

---
---

## PHASE 3: iOS App MVP (SwiftUI)

**Ziel:** Eine vollstaendige, benutzbare iOS-App die Push-Ups trackt, Zeitguthaben anzeigt und eine Workout-Historie bietet. Lauffaehig auf dem Simulator und physischen Geraeten.

---

### Task 3.1: iOS Projekt-Setup und KMP Framework-Einbindung

**Beschreibung:**
Erstelle das Xcode-Projekt fuer die iOS-App und binde das KMP shared-Framework ein. Konfiguriere die Build-Pipeline so, dass Aenderungen am KMP-Code automatisch in das iOS-Framework uebernommen werden.

**Akzeptanzkriterien:**
- Xcode-Projekt (iosApp) ist erstellt mit SwiftUI App Lifecycle
- KMP shared-Modul wird als XCFramework eingebunden
- shared-Code ist aus Swift heraus aufrufbar (import shared)
- Koin/DI ist von iOS-Seite initialisiert
- App startet auf dem Simulator (und physischem Geraet wenn verfuegbar)
- Build-Prozess: ./gradlew :shared:assembleXCFramework -> Xcode Build
- Minimum Deployment Target: iOS 16.0

**Abhaengigkeiten:** Phase 1 (komplett)

**Schaetzung:** M (Mittel)

---

### Task 3.2: App-Navigation und Tab-Struktur

**Beschreibung:**
Implementiere die grundlegende App-Navigation mit einer Tab-Bar. Die App hat 4 Tabs: Dashboard, Workout (Kamera starten), Historie und Einstellungen. Erstelle die leeren Screens als Platzhalter.

**Akzeptanzkriterien:**
- TabView mit 4 Tabs: Dashboard, Workout, History, Settings
- Jeder Tab hat ein passendes SF Symbol als Icon
- Navigation innerhalb der Tabs (NavigationStack)
- Leere Placeholder-Views fuer jeden Screen
- Tab-Auswahl bleibt bei App-Neustart nicht persistent (immer Dashboard)
- Farb-Schema / Grundlegendes Theming (Akzentfarbe definiert)

**Abhaengigkeiten:** Task 3.1

**Schaetzung:** S (Klein)

---

### Task 3.3: Dashboard Screen

**Beschreibung:**
Implementiere den Dashboard-Screen als Hauptansicht der App. Zeigt das aktuelle Zeitguthaben prominent an, dazu Tages-Statistiken und einen Quick-Start-Button fuer ein Workout.

**Akzeptanzkriterien:**
- Grosser, prominenter Zeitguthaben-Anzeiger (Stunden:Minuten:Sekunden)
- Kreisfoermiger Fortschrittsindikator oder aehnliche Visualisierung
- Tages-Statistik Karte: Heutige Push-Ups, heutige Sessions, heute verdiente Zeit
- Wochen-Statistik: Kleine Bar-Chart oder Zahlen fuer die letzten 7 Tage
- "Workout starten" Button (navigiert zum Workout-Tab)
- Letzte Session: Kurze Zusammenfassung der letzten Workout-Session
- Pull-to-Refresh um Daten zu aktualisieren
- Leerer Zustand wenn noch keine Workouts gemacht wurden ("Starte dein erstes Workout!")
- Daten kommen aus GetTimeCreditUseCase und GetWorkoutStatsUseCase (KMP)

**Abhaengigkeiten:** Task 3.2, Phase 1

**Schaetzung:** M (Mittel)

---

### Task 3.4: Workout Screen (Kamera + Live-Tracking)

**Beschreibung:**
Implementiere den Workout-Screen der die Kamera zeigt und Push-Ups in Echtzeit zaehlt. Der Screen nutzt die Kamera-Komponente und die Push-Up-Erkennung aus Phase 2.

**Akzeptanzkriterien:**
- Kamera-Preview als Hintergrund (Vollbild oder grosser Bereich)
- Live Push-Up Counter gross und gut sichtbar eingeblendet
- Aktueller Form-Score Anzeige (z.B. Farbcodiert: gruen/gelb/rot)
- Session-Timer (wie lange laeuft das Workout schon)
- Pose-Overlay: Erkannte Koerperpunkte als Linien/Punkte auf dem Kamerabild (optional ein/ausschaltbar)
- Start/Pause/Stop Buttons
- Countdown (3, 2, 1) vor dem Start
- Bestaetigung beim Stoppen ("Workout wirklich beenden?")
- Kamerawechsel-Button (Front/Rueck)
- Bildschirm bleibt an waehrend des Workouts (UIApplication.shared.isIdleTimerDisabled)

**Abhaengigkeiten:** Task 3.2, Phase 2

**Schaetzung:** L (Gross)

---

### Task 3.5: Workout-Abschluss Screen

**Beschreibung:**
Implementiere den Screen der nach Beendigung eines Workouts angezeigt wird. Zeigt eine Zusammenfassung der Session: Anzahl Push-Ups, Dauer, Durchschnittsqualitaet und das verdiente Zeitguthaben.

**Akzeptanzkriterien:**
- Anzeige nach Beendigung des Workouts (FinishWorkoutUseCase Ergebnis)
- Grosse Zahl: Anzahl Push-Ups
- Verdientes Zeitguthaben prominent angezeigt ("+ 5 Minuten verdient!")
- Session-Dauer
- Durchschnittliche Qualitaet (als Score oder Sterne)
- Vergleich zum Durchschnitt ("12% besser als dein Durchschnitt")
- "Zurueck zum Dashboard" Button
- Optional: Share-Button (Screenshot/Text teilen)
- Animation beim Einblenden der Ergebnisse (Zahlen zaehlen hoch)

**Abhaengigkeiten:** Task 3.4

**Schaetzung:** M (Mittel)

---

### Task 3.6: History Screen

**Beschreibung:**
Implementiere den History-Screen der alle vergangenen Workouts in einer chronologischen Liste anzeigt. Optional mit Kalender-Ansicht um Tage mit Workouts hervorzuheben.

**Akzeptanzkriterien:**
- Liste aller vergangenen WorkoutSessions, sortiert nach Datum (neuste zuerst)
- Pro Eintrag: Datum, Uhrzeit, Push-Up Anzahl, Dauer, verdiente Zeit, Qualitaet
- Gruppierung nach Tagen (Section Headers)
- Detail-Ansicht bei Tap: Volle Session-Details inkl. einzelne Push-Up-Records
- Kalender-Ansicht (Toggle): Monatskalender mit markierten Tagen
- Leerer Zustand: "Noch keine Workouts vorhanden"
- Loesch-Funktion (Swipe-to-Delete) mit Bestaetigung
- Daten kommen aus WorkoutSessionRepository (KMP)

**Abhaengigkeiten:** Task 3.2, Phase 1

**Schaetzung:** M (Mittel)

---

### Task 3.7: Settings Screen

**Beschreibung:**
Implementiere den Einstellungen-Screen. Hier kann der Benutzer die Push-Up-Rate konfigurieren, den Quality Multiplier aktivieren/deaktivieren und ein taegliches Guthaben-Limit setzen.

**Akzeptanzkriterien:**
- Einstellung: Push-Ups pro Minute Guthaben (Stepper oder Slider, Bereich 1-50, Default 10)
- Einstellung: Quality Multiplier an/aus (Toggle)
- Einstellung: Taegliches Guthaben-Limit (optional, Picker in Minuten)
- Einstellung: Kamera-Praeferenz (Front/Rueck als Default)
- Einstellung: Pose-Overlay an/aus
- Info-Sektion: Erklaerung der Zeitguthaben-Formel
- Alle Einstellungen werden sofort ueber UpdateUserSettingsUseCase (KMP) gespeichert
- App-Version und Build-Nummer angezeigt
- Link zu Datenschutzerklaerung (Platzhalter-URL reicht)

**Abhaengigkeiten:** Task 3.2, Phase 1

**Schaetzung:** M (Mittel)

---

### Task 3.8: App-Icon, Launch Screen und visuelles Polish

**Beschreibung:**
Erstelle ein App-Icon, einen Launch Screen und sorge fuer ein einheitliches visuelles Erscheinungsbild der App. Definiere Farben, Typografie und Spacing-Konventionen.

**Akzeptanzkriterien:**
- App-Icon in allen noetigen Groessen (Asset Catalog)
- Launch Screen (einfach: App-Logo auf Hintergrundfarbe)
- Definierte Farbpalette (Primaerfarbe, Sekundaerfarbe, Hintergrund, Text)
- Dark Mode Unterstuetzung (Light + Dark Appearance)
- Konsistente Abstande und Schriftgroessen ueber alle Screens
- Keine Placeholder-Texte oder -Bilder mehr in der UI
- App-Name korrekt in allen Kontexten (Homescreen, Settings)

**Abhaengigkeiten:** Task 3.3 - 3.7 (nach den Screens)

**Schaetzung:** M (Mittel)

---

### Task 3.9: Lokale Benachrichtigungen

**Beschreibung:**
Implementiere lokale Push-Benachrichtigungen die den Benutzer an seine Push-Ups erinnern. Konfigurierbar in den Einstellungen.

**Akzeptanzkriterien:**
- Benachrichtigungsberechtigung wird beim ersten Start angefragt
- Taegliche Erinnerung: "Zeit fuer Push-Ups!" (konfigurierbare Uhrzeit)
- Streak-Erinnerung: "Du hast heute noch kein Workout gemacht -- dein Streak ist in Gefahr!"
- Guthaben-Hinweis: "Dein Zeitguthaben ist aufgebraucht -- mach Push-Ups fuer mehr Screen-Time"
- Einstellungen: Benachrichtigungen an/aus, Uhrzeit waehlen
- Benachrichtigungen werden nicht geschickt wenn heute bereits ein Workout gemacht wurde

**Abhaengigkeiten:** Task 3.7 (Settings)

**Schaetzung:** M (Mittel)

---
---

## PHASE 4: Screen-Time Kontrolle (iOS)

**Ziel:** Das verdiente Zeitguthaben wird beim Nutzen von Social Media / Streaming-Apps verbraucht. Wenn das Guthaben aufgebraucht ist, werden diese Apps blockiert. Benoetigt Apple Developer Account.

**Wichtig:** Apple's Screen Time API (Family Controls / Managed Settings / Device Activity) hat strenge Einschraenkungen. Vor der Implementierung muss eine gruendliche Recherche stattfinden.

---

### Task 4.1: Screen Time API Recherche und Machbarkeitspruefung

**Beschreibung:**
Fuehre eine detaillierte Recherche zur Apple Screen Time API durch. Dokumentiere was moeglich ist, was nicht, welche Einschraenkungen gelten und welche Alternativen es gibt. Das Ergebnis ist ein Dokument das die technische Machbarkeit bewertet.

**Akzeptanzkriterien:**
- Dokumentation der verfuegbaren Frameworks: Family Controls, Managed Settings, Device Activity
- Klaerung: Kann eine App sich SELBST Screen-Time-Limits setzen (oder nur fuer "Family"/Kinder)?
- Klaerung: Welche Entitlements sind noetig? Braucht man eine spezielle Apple-Genehmigung?
- Klaerung: Kann man spezifische Apps (Instagram, TikTok, Netflix) identifizieren und blockieren?
- Klaerung: Kann der User die Blockierung einfach umgehen?
- Alternativen wenn Screen Time API nicht nutzbar: VPN-basierte Loesung, DNS-basiert, Focus-Mode Integration
- Bewertung: Machbar / Teilweise machbar / Nicht machbar -- mit Begruendung
- Ergebnis-Dokument im Repo (SCREEN_TIME_RESEARCH.md)

**Abhaengigkeiten:** Keine (kann frueh gestartet werden, sogar parallel zu Phase 1)

**Schaetzung:** M (Mittel)

---

### Task 4.2: Family Controls Entitlement und Projekt-Setup

**Beschreibung:**
Beantrage das Family Controls Entitlement bei Apple und konfiguriere das Xcode-Projekt fuer die Screen Time APIs. Erstelle die noetige App Extension (Device Activity Monitor).

**Akzeptanzkriterien:**
- Family Controls Entitlement ist beantragt und genehmigt (Apple Developer Account noetig)
- Xcode-Projekt hat das Family Controls Capability aktiviert
- Device Activity Monitor Extension ist als Target hinzugefuegt
- Shield Configuration Extension ist als Target hinzugefuegt (fuer Custom Block Screen)
- AuthorizationCenter.shared.requestAuthorization() funktioniert
- App erhaelt Berechtigung zur App-Kontrolle

**Abhaengigkeiten:** Task 4.1 (Machbarkeit bestaetigt), Apple Developer Account

**Schaetzung:** M (Mittel)

---

### Task 4.3: App-Kategorie-Auswahl (Activity Picker)

**Beschreibung:**
Implementiere einen Screen auf dem der Benutzer auswaehlen kann, welche Apps/Kategorien Zeitguthaben verbrauchen sollen. Nutze den FamilyActivityPicker von Apple.

**Akzeptanzkriterien:**
- FamilyActivityPicker ist integriert (Apple's vorgefertigter UI-Picker)
- Benutzer kann einzelne Apps und/oder App-Kategorien auswaehlen
- Auswahl wird lokal persistiert (UserDefaults oder KMP Core)
- Vorauswahl-Vorschlaege: "Social Media", "Unterhaltung", "Spiele"
- Auswahl ist in den Settings aenderbar
- Ausgewaehlte Apps/Kategorien werden als FamilyActivitySelection gespeichert

**Abhaengigkeiten:** Task 4.2

**Schaetzung:** M (Mittel)

---

### Task 4.4: Guthaben-Timer und App-Blockierung

**Beschreibung:**
Implementiere die Kernlogik: Wenn der Benutzer eine der ausgewaehlten Apps oeffnet, laeuft das Zeitguthaben runter. Wenn es bei 0 ankommt, wird die App blockiert (Shield).

**Akzeptanzkriterien:**
- DeviceActivityMonitor Extension erkennt wenn eine ueberwachte App gestartet wird
- Ein Timer zaehlt das Guthaben herunter (SpendTimeCreditUseCase)
- Bei Guthaben = 0: ManagedSettingsStore blockiert die ausgewaehlten Apps (Shield)
- Shield zeigt einen Custom Screen: "Guthaben aufgebraucht -- mach Push-Ups fuer mehr Zeit"
- Button auf dem Shield: "Workout starten" (oeffnet die PushUp App)
- Blockierung wird aufgehoben sobald neues Guthaben verdient wird
- Guthaben-Stand wird in Echtzeit aktualisiert (im KMP Core)
- Edge Case: App geht in den Hintergrund -- Timer pausiert oder laeuft weiter (konfigurierbar)

**Abhaengigkeiten:** Task 4.3, Phase 1 (SpendTimeCreditUseCase)

**Schaetzung:** XL (Sehr Gross)

---

### Task 4.5: Benachrichtigungen fuer Screen-Time

**Beschreibung:**
Implementiere Benachrichtigungen die den Benutzer warnen bevor sein Guthaben aufgebraucht ist, und ihn informieren wenn Apps blockiert wurden.

**Akzeptanzkriterien:**
- Warnung bei 50% Guthaben: "Du hast noch X Minuten Screen-Time"
- Warnung bei 25% Guthaben: "Nur noch X Minuten -- mach Push-Ups fuer mehr Zeit"
- Warnung bei 5 Minuten Restguthaben: "Gleich ist deine Screen-Time aufgebraucht!"
- Benachrichtigung bei Blockierung: "Deine ausgewaehlten Apps sind jetzt gesperrt"
- Benachrichtigung bei neuem Guthaben: "Workout abgeschlossen! Du hast X Minuten verdient"
- Schwellwerte sind in den Settings konfigurierbar
- Benachrichtigungen koennen an/ausgeschaltet werden

**Abhaengigkeiten:** Task 4.4

**Schaetzung:** S (Klein)

---

### Task 4.6: Bypass-Schutz und Fairness-Regeln

**Beschreibung:**
Implementiere Schutzmassnahmen damit der Benutzer die Blockierung nicht einfach umgehen kann. Gleichzeitig muessen faire Regeln gelten (Notfall-Zugriff, etc.).

**Akzeptanzkriterien:**
- Kein einfaches Deaktivieren der Blockierung ohne Push-Ups (kein "Skip"-Button)
- Notfall-Override: Bei 3x langem Druecken kann die Sperre fuer 5 Minuten aufgehoben werden (mit Cooldown, max 2x pro Tag)
- Wenn die PushUp-App deinstalliert wird: Blockierung bleibt bestehen (Device Activity Monitor Extension)
- Wenn der Benutzer die Screen-Time-Berechtigung widerruft: App zeigt Hinweis, Blockierung wird aufgehoben
- Keine Manipulation der Uhrzeit moeglich (Server-Time oder Plausibilitaetspruefung)
- Taeglicher Reset: Guthaben verfaellt NICHT am Tagesende (akkumuliert sich)

**Abhaengigkeiten:** Task 4.4

**Schaetzung:** M (Mittel)

---
---

## PHASE 5: Erweiterungen (Zukunft)

**Ziel:** Die App wird um zusaetzliche Features erweitert. Jeder Task hier ist unabhaengig und kann einzeln priorisiert werden.

---

### Task 5.1: Apple Watch App (watchOS)

**Beschreibung:**
Erstelle eine Companion-App fuer die Apple Watch. Die Watch kann Workouts starten, Push-Ups zaehlen (ueber den Beschleunigungssensor, ohne Kamera) und das Ergebnis an die iPhone-App senden.

**Akzeptanzkriterien:**
- watchOS App Target im Xcode-Projekt
- Watch-App zeigt aktuelles Zeitguthaben
- Workout starten/stoppen von der Watch
- Push-Up Erkennung ueber Accelerometer + Gyroscope (Armbewegung beim Push-Up)
- WatchConnectivity: Workout-Daten werden an iPhone synchronisiert
- Complications: Zeitguthaben auf dem Watch-Face

**Abhaengigkeiten:** Phase 3 (MVP)

**Schaetzung:** XL (Sehr Gross)

---

### Task 5.2: Apple HealthKit Integration

**Beschreibung:**
Integriere Apple HealthKit um Workouts in die Health-App einzutragen und ggf. Daten aus Health zu lesen (z.B. andere Workouts als Bonus-Guthaben).

**Akzeptanzkriterien:**
- HealthKit Berechtigung wird angefragt
- Abgeschlossene Workouts werden als HKWorkout in HealthKit geschrieben
- Workout-Typ: .functionalStrengthTraining oder .traditionalStrengthTraining
- Kalorien werden geschaetzt und eingetragen
- Optional: Andere Workouts aus HealthKit lesen und als Bonus-Guthaben gutschreiben
- Settings: HealthKit an/aus

**Abhaengigkeiten:** Phase 3 (MVP)

**Schaetzung:** M (Mittel)

---

### Task 5.3: Weitere Uebungen (Squats, Sit-Ups, etc.)

**Beschreibung:**
Erweitere die Pose Detection um weitere Uebungen zu erkennen. Jede Uebung hat ihren eigenen Erkennungsalgorithmus und eigene Qualitaetskriterien.

**Akzeptanzkriterien:**
- Abstrakte Basis-Klasse "ExerciseDetector" mit gemeinsamer Logik
- Squats: Erkennung ueber Knie-/Hueftwinkel
- Sit-Ups: Erkennung ueber Oberkörper-Huefte-Winkel
- Burpees: Erkennung der Phasensequenz (Stehen -> Liegestuetz -> Sprung)
- Plank: Erkennung der Position + Timer (Haltezeit)
- Konfigurierbare Guthaben-Rate pro Uebungstyp
- Uebungsauswahl im Workout-Screen

**Abhaengigkeiten:** Phase 2 (Push-Up Erkennung)

**Schaetzung:** XL (Sehr Gross)

---

### Task 5.4: Android App

**Beschreibung:**
Erstelle die Android-Version der App mit Jetpack Compose als UI-Framework. Der KMP Shared Core wird direkt eingebunden. Die Kamera-Erkennung nutzt Google ML Kit statt Apple Vision.

**Akzeptanzkriterien:**
- Android-Modul (androidApp) im KMP-Projekt
- Jetpack Compose UI mit gleicher Funktionalitaet wie iOS (Dashboard, Workout, History, Settings)
- CameraX fuer Kamera-Zugriff
- Google ML Kit Pose Detection fuer Push-Up-Erkennung
- Push-Up Erkennungsalgorithmus wird wiederverwendet (ggf. in shared/ verschieben)
- SQLDelight Android-Driver
- Material 3 Design
- Minimum SDK: Android 8.0 (API 26)

**Abhaengigkeiten:** Phase 1 (KMP Core), Phase 2 (Algorithmus-Logik)

**Schaetzung:** XL (Sehr Gross)

---

### Task 5.5: Backend und Cloud-Sync

**Beschreibung:**
Erstelle ein Backend fuer User-Accounts und Cloud-Synchronisation. Workouts und Guthaben werden geraeteuebergreifend synchronisiert.

**Akzeptanzkriterien:**
- Backend-Service (z.B. Ktor/Kotlin, Firebase, oder Supabase)
- User-Registrierung und Login (Email + Apple Sign-In)
- Cloud-Sync: Workouts und Guthaben werden auf dem Server gespeichert
- Offline-First: App funktioniert ohne Internet, synchronisiert bei Verbindung
- Konflikt-Behandlung bei gleichzeitigen Aenderungen
- API-Sicherheit: Authentifizierung, Rate-Limiting

**Abhaengigkeiten:** Phase 3 (MVP)

**Schaetzung:** XL (Sehr Gross)

---

### Task 5.6: Soziale Features

**Beschreibung:**
Fuege soziale Elemente hinzu: Challenges mit Freunden, Leaderboards, Workouts teilen.

**Akzeptanzkriterien:**
- Freunde hinzufuegen (via Code, QR, oder Kontakte)
- Challenges erstellen: "Wer macht diese Woche mehr Push-Ups?"
- Leaderboard: Woechentliche/Monatliche Rangliste unter Freunden
- Activity-Feed: Sehen was Freunde machen (mit Opt-In)
- Workout-Ergebnisse teilen (Instagram Story, WhatsApp, etc.)
- Push-Benachrichtigungen bei Challenge-Updates

**Abhaengigkeiten:** Task 5.5 (Backend)

**Schaetzung:** XL (Sehr Gross)

---

### Task 5.7: Gamification

**Beschreibung:**
Fuege Gamification-Elemente hinzu die die Motivation steigern: Achievements, Streaks, Levels, taegliche Challenges.

**Akzeptanzkriterien:**
- Achievement-System: "Erster Push-Up", "100 Push-Ups", "7-Tage-Streak", "1000 Push-Ups gesamt", etc.
- Streak-Tracker: Aufeinanderfolgende Tage mit mindestens einem Workout
- Level-System: XP fuer Push-Ups, Level-Up bei Schwellwerten
- Taegliche Challenge: "Mach heute 50 Push-Ups" (variiert taeglich)
- Visuelle Belohnungen: Animationen bei Achievements und Level-Ups
- Achievement-Galerie im Profil

**Abhaengigkeiten:** Phase 3 (MVP)

**Schaetzung:** L (Gross)

---

### Task 5.8: Home Screen Widget

**Beschreibung:**
Erstelle ein iOS Home Screen Widget das das aktuelle Zeitguthaben und die heutige Push-Up-Anzahl anzeigt.

**Akzeptanzkriterien:**
- WidgetKit Extension im Xcode-Projekt
- Small Widget: Zeitguthaben (Stunden:Minuten)
- Medium Widget: Zeitguthaben + heutige Push-Ups + Streak
- Large Widget: Zeitguthaben + Wochen-Ueberblick (Bar-Chart)
- Widgets aktualisieren sich regelmaessig (Timeline Provider)
- Tap auf Widget oeffnet die App (Deep Link zum Dashboard)
- Lock Screen Widget (iOS 16+): Zeitguthaben

**Abhaengigkeiten:** Phase 3 (MVP)

**Schaetzung:** M (Mittel)

---
---

## Groessen-Legende

| Groesse | Bedeutung | Grober Zeitrahmen |
|---------|-----------|-------------------|
| S (Klein) | Einfache, klar definierte Aufgabe | 2-4 Stunden |
| M (Mittel) | Moderate Komplexitaet, einige Entscheidungen | 0.5-1.5 Tage |
| L (Gross) | Komplex, mehrere Teilaspekte | 2-4 Tage |
| XL (Sehr Gross) | Sehr komplex, viele Unbekannte | 1-2 Wochen |

---

## Empfohlene Reihenfolge

```
Phase 1: 1.1 -> 1.2 + 1.3 (parallel) -> 1.4 -> 1.5 -> 1.6 -> 1.7-1.13 (parallel moeglich) -> 1.14 -> 1.15
Phase 2: 2.1 -> 2.2 -> 2.3 -> 2.4 -> 2.5 -> 2.6
Phase 3: 3.1 -> 3.2 -> 3.3 + 3.6 + 3.7 (parallel) -> 3.4 -> 3.5 -> 3.8 -> 3.9
Phase 4: 4.1 (frueh starten!) -> 4.2 -> 4.3 -> 4.4 -> 4.5 + 4.6 (parallel)
Phase 5: Unabhaengig priorisierbar
```

**Tipp:** Task 4.1 (Screen Time API Recherche) kann schon waehrend Phase 1 gestartet werden, damit du frueh weisst ob die Screen-Time-Kontrolle wie geplant moeglich ist.
