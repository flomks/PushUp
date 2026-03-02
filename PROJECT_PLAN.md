# PushUp App -- Projektplan

## Vision

Eine App die per Kamera Liegestuetze (Push-Ups) trackt, diese in Zeitguthaben umwandelt, und dieses Guthaben spaeter als Screen-Time-Budget fuer Social Media / Netflix etc. genutzt werden kann.

**Kernprinzip:** Erst bewegen, dann konsumieren.

---

## Tech-Stack

| Komponente | Technologie | Begründung |
|------------|-------------|------------|
| **Shared Core** | Kotlin Multiplatform (KMP) | Einmal schreiben, iOS + Android nutzen |
| **iOS App** | SwiftUI + KMP Framework | Native iOS-Erlebnis |
| **Android App** (spaeter) | Jetpack Compose + KMP | Native Android-Erlebnis |
| **Lokale DB** | SQLDelight (KMP) | Cross-Platform SQLite-Wrapper |
| **Push-Up Erkennung iOS** | Apple Vision Framework | On-Device Pose Estimation |
| **Push-Up Erkennung Android** (spaeter) | Google ML Kit | On-Device Pose Estimation |
| **Build-System** | Gradle (KMP) + Xcode (iOS) | Standard fuer KMP-Projekte |

---

## Projektstruktur

```
pushup-app/
├── shared/                         # KMP Shared Module
│   └── src/
│       ├── commonMain/kotlin/
│       │   ├── domain/
│       │   │   ├── model/          # Datenmodelle
│       │   │   ├── usecase/        # Business-Logik / Use-Cases
│       │   │   └── repository/     # Repository-Interfaces
│       │   ├── data/
│       │   │   ├── repository/     # Repository-Implementierungen
│       │   │   ├── local/          # Lokale Datenquellen
│       │   │   └── mapper/         # Daten-Mapper
│       │   └── util/               # Hilfsfunktionen
│       ├── commonTest/kotlin/      # Shared Unit Tests
│       ├── iosMain/kotlin/         # iOS-spezifische Erwartungen
│       └── androidMain/kotlin/     # Android-spezifische Erwartungen (spaeter)
│
├── iosApp/                         # Native iOS App
│   ├── iosApp/
│   │   ├── App/                    # App Entry Point
│   │   ├── Features/
│   │   │   ├── Dashboard/          # Hauptscreen mit Guthaben-Anzeige
│   │   │   ├── Workout/            # Kamera + Live Push-Up Tracking
│   │   │   ├── History/            # Vergangene Workouts
│   │   │   └── Settings/           # Einstellungen
│   │   ├── Camera/                 # AVFoundation Kamera-Setup
│   │   ├── PoseDetection/          # Vision Framework Pose Estimation
│   │   └── Shared/                 # Gemeinsame iOS-Komponenten
│   └── iosApp.xcodeproj
│
└── androidApp/                     # Native Android App (spaeter)
```

---

## Datenmodell (Core)

### WorkoutSession
```
- id: UUID
- startedAt: Timestamp
- endedAt: Timestamp?
- pushUpCount: Int
- earnedTimeCredits: Long (Sekunden)
- quality: Float (0.0 - 1.0, Ausfuehrungsqualitaet)
```

### TimeCredit
```
- id: UUID
- totalEarnedSeconds: Long
- totalSpentSeconds: Long
- availableSeconds: Long (berechnet)
- lastUpdatedAt: Timestamp
```

### PushUpRecord (einzelner Push-Up innerhalb einer Session)
```
- id: UUID
- sessionId: UUID
- timestamp: Timestamp
- durationMs: Long (Dauer eines einzelnen Push-Ups)
- depthScore: Float (wie tief)
- formScore: Float (Ausfuehrungsqualitaet)
```

### UserSettings
```
- pushUpsPerMinuteCredit: Int (default: 10 Push-Ups = 1 Minute)
- qualityMultiplier: Boolean (bessere Form = mehr Zeit?)
- dailyCreditCap: Long? (max. Guthaben pro Tag, optional)
```

---

## Zeitguthaben-Formel (Initial)

**Basis-Formel:**
```
earnedMinutes = pushUpCount / pushUpsPerMinuteCredit
```

**Beispiel (Default-Einstellung: 10 Push-Ups = 1 Minute):**
- 10 Push-Ups = 1 Minute Screen-Time
- 50 Push-Ups = 5 Minuten Screen-Time
- 100 Push-Ups = 10 Minuten Screen-Time

**Spaetere Erweiterung (Quality Multiplier):**
```
earnedMinutes = (pushUpCount / pushUpsPerMinuteCredit) * qualityMultiplier
```
- Saubere Ausfuehrung (formScore > 0.8): qualityMultiplier = 1.5x
- Normale Ausfuehrung (formScore 0.5-0.8): qualityMultiplier = 1.0x
- Schlechte Ausfuehrung (formScore < 0.5): qualityMultiplier = 0.7x

---

## Phasen-Uebersicht

### Phase 1: Projekt-Setup & Core-Logik
**Ziel:** Grundgeruest steht, Business-Logik funktioniert und ist getestet.
**Kein Apple Developer Account noetig.**

- [ ] KMP Projekt-Setup (Gradle, Kotlin, SQLDelight)
- [ ] Datenmodelle definieren (WorkoutSession, TimeCredit, PushUpRecord)
- [ ] SQLDelight Schema & Queries
- [ ] Repository-Pattern implementieren
- [ ] Use-Cases: Workout starten/beenden, Guthaben berechnen
- [ ] Use-Cases: Guthaben abfragen, Statistiken
- [ ] Unit Tests fuer alle Use-Cases
- [ ] CI Pipeline (GitHub Actions: Build + Test)

### Phase 2: Push-Up Erkennung (iOS)
**Ziel:** Kamera erkennt Push-Ups zuverlaessig und zaehlt sie.

- [ ] AVFoundation Kamera-Setup (Frontkamera / Rueckkamera)
- [ ] Apple Vision Framework Integration (Body Pose Detection)
- [ ] Push-Up Erkennungsalgorithmus (Hoch-/Runter-Zyklen)
- [ ] Echtzeit-Zaehler Logik
- [ ] Form-Bewertung (Tiefe, Koerperposition)
- [ ] Edge-Case Handling (Beleuchtung, Winkel, Entfernung)
- [ ] Performance-Optimierung (Real-Time auf aelteren Geraeten)

### Phase 3: iOS App MVP
**Ziel:** Funktionale iOS-App die Push-Ups trackt und Guthaben anzeigt.

- [ ] SwiftUI Projekt-Setup mit KMP Framework-Einbindung
- [ ] Dashboard Screen (Aktuelles Guthaben, Tages-Statistik)
- [ ] Workout Screen (Kamera + Live-Counter + Timer)
- [ ] Workout-Abschluss Screen (Zusammenfassung)
- [ ] History Screen (vergangene Workouts, Kalender-Ansicht)
- [ ] Settings Screen (Push-Up-Rate konfigurieren)
- [ ] App-Icon & Launch Screen
- [ ] Lokale Benachrichtigungen ("Zeit fuer Push-Ups!")

### Phase 4: Screen-Time Kontrolle (iOS)
**Ziel:** Guthaben wird beim Nutzen von Social Media / Streaming verbraucht.
**Apple Developer Account noetig (Screen Time API / Family Controls).**

- [ ] Screen Time API / Family Controls Framework Recherche
- [ ] App-Kategorie-Auswahl (welche Apps verbrauchen Guthaben)
- [ ] Guthaben-Timer (laeuft runter bei Nutzung)
- [ ] App-Blockierung wenn Guthaben = 0
- [ ] Benachrichtigungen ("Noch 5 Minuten Guthaben")
- [ ] Bypass-Schutz (kein einfaches Umgehen)

### Phase 5: Erweiterungen (Zukunft)
- [ ] Apple Watch App (Workout direkt von der Watch starten)
- [ ] Apple HealthKit Integration (Workouts in Health eintragen)
- [ ] Weitere Uebungen (Squats, Sit-Ups, Burpees, Planks)
- [ ] Android App (Jetpack Compose + KMP Core + ML Kit)
- [ ] Backend & User-Accounts (Cloud-Sync)
- [ ] Soziale Features (Challenges, Leaderboards, Freunde)
- [ ] Gamification (Achievements, Streaks, Levels)
- [ ] Widget (Guthaben auf Homescreen)

---

## Abhaengigkeiten & Risiken

| Risiko | Auswirkung | Mitigation |
|--------|-----------|------------|
| Push-Up Erkennung ungenau | Schlechte User-Experience | Frueh testen, Fallback auf manuelles Zaehlen |
| Screen Time API Einschraenkungen | Feature ggf. nicht wie geplant moeglich | Recherche in Phase 1, alternativen Plan haben |
| Apple Developer Account Kosten (99$/Jahr) | Blockiert Deployment + Screen Time API | Phasen 1-3 ohne Account machbar, Account erst fuer Phase 4 |
| Performance auf aelteren iPhones | App laeuft nicht fluessig | Frueh auf aelteren Geraeten testen |
| KMP Learning Curve | Langsamere Entwicklung | Gute Doku nutzen, einfach starten |

---

## Naechste Schritte

**Jetzt starten mit Phase 1:**
1. KMP Projekt-Grundgeruest aufsetzen
2. Datenmodelle implementieren
3. Core Business-Logik schreiben
4. Unit Tests
