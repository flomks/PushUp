# Screen Time -- Xcode Setup Guide

**Stand: Maerz 2026**
**App: PushUp (Bundle ID: `com.flomks.pushup`)**

Alle Swift-Dateien sind bereits im Repository. Diese Anleitung beschreibt
die Schritte, die manuell in Xcode und im Apple Developer Portal gemacht
werden muessen.

---

## Schritt 1: App Group im Developer Portal erstellen

1. Oeffne **https://developer.apple.com/account**
2. Gehe zu **Certificates, Identifiers & Profiles > Identifiers**
3. Klicke oben links auf das Dropdown und waehle **App Groups**
4. Klicke **+** oben rechts
5. Fuell aus:
   - **Description:** `PushUp App Group`
   - **Identifier:** `group.com.flomks.pushup`
6. Klicke **Continue** und dann **Register**

---

## Schritt 2: Family Controls fuer App ID aktivieren

1. Gehe zu **Certificates, Identifiers & Profiles > Identifiers**
2. Klicke auf `com.flomks.pushup`
3. Scrolle zu **Family Controls** und aktiviere den Haken
4. Klicke **Save**

---

## Schritt 3: Vier Extension Targets in Xcode erstellen

Oeffne `iosApp/iosApp.xcodeproj` in Xcode.

### 3.1 -- DeviceActivity Monitor Extension

1. **File > New > Target**
2. Waehle **Device Activity Monitor Extension**
3. Fuell aus:
   - **Product Name:** `ScreenTimeMonitor`
   - **Bundle Identifier:** `com.flomks.pushup.ScreenTimeMonitor`
   - **Team:** dein Apple Developer Team
4. Klicke **Finish**
5. Xcode erstellt automatisch eine leere `DeviceActivityMonitorExtension.swift`
6. **Ersetze** den Inhalt dieser Datei mit dem Inhalt von:
   `iosApp/ScreenTimeMonitor/DeviceActivityMonitorExtension.swift`
7. Gehe zu **Target: ScreenTimeMonitor > Signing & Capabilities**
8. Klicke **+ Capability** und fuege hinzu:
   - **Family Controls**
   - **App Groups** (trage `group.com.flomks.pushup` ein)
9. Ersetze die auto-generierte `.entitlements`-Datei mit:
   `iosApp/ScreenTimeMonitor/ScreenTimeMonitor.entitlements`

### 3.2 -- Shield Configuration Extension

1. **File > New > Target**
2. Waehle **Shield Configuration Extension**
3. Fuell aus:
   - **Product Name:** `ShieldConfiguration`
   - **Bundle Identifier:** `com.flomks.pushup.ShieldConfiguration`
4. Klicke **Finish**
5. Ersetze den Inhalt der generierten Swift-Datei mit:
   `iosApp/ShieldConfiguration/ShieldConfigurationExtension.swift`
6. Gehe zu **Target: ShieldConfiguration > Signing & Capabilities**
7. Fuege hinzu: **Family Controls**, **App Groups** (`group.com.flomks.pushup`)
8. Ersetze die `.entitlements`-Datei mit:
   `iosApp/ShieldConfiguration/ShieldConfiguration.entitlements`

### 3.3 -- Shield Action Extension

1. **File > New > Target**
2. Waehle **Shield Action Extension**
3. Fuell aus:
   - **Product Name:** `ShieldAction`
   - **Bundle Identifier:** `com.flomks.pushup.ShieldAction`
4. Klicke **Finish**
5. Ersetze den Inhalt der generierten Swift-Datei mit:
   `iosApp/ShieldAction/ShieldActionExtension.swift`
6. Gehe zu **Target: ShieldAction > Signing & Capabilities**
7. Fuege hinzu: **Family Controls**, **App Groups** (`group.com.flomks.pushup`)
8. Ersetze die `.entitlements`-Datei mit:
   `iosApp/ShieldAction/ShieldAction.entitlements`

### 3.4 -- DeviceActivity Report Extension (NEU -- iOS 16.4+)

Diese Extension ermoeglicht das Anzeigen von echten Per-App-Nutzungsdaten
direkt aus dem iOS Screen Time System. Sie ist fuer die Per-App-Statistiken
im Stats-Tab erforderlich.

1. **File > New > Target**
2. Waehle **Device Activity Report Extension**
3. Fuell aus:
   - **Product Name:** `DeviceActivityReport`
   - **Bundle Identifier:** `com.flomks.pushup.DeviceActivityReport`
4. Klicke **Finish**
5. Ersetze den Inhalt der generierten Swift-Datei mit:
   `iosApp/DeviceActivityReport/DeviceActivityReportExtension.swift`
6. Gehe zu **Target: DeviceActivityReport > Signing & Capabilities**
7. Fuege hinzu: **Family Controls**, **App Groups** (`group.com.flomks.pushup`)
8. Ersetze die `.entitlements`-Datei mit:
   `iosApp/DeviceActivityReport/DeviceActivityReport.entitlements`
9. Stelle sicher, dass **Minimum Deployment Target** auf **iOS 16.4** gesetzt ist

---

## Schritt 4: Haupt-Target konfigurieren

1. Klicke auf das Projekt-Root in der linken Seitenleiste
2. Waehle **Target: iosApp**
3. Gehe zu **Signing & Capabilities**
4. Klicke **+ Capability** und fuege hinzu:
   - **Family Controls**
   - **App Groups** (trage `group.com.flomks.pushup` ein)
5. Stelle sicher, dass `iosApp.entitlements` die neuen Eintraege enthaelt
   (bereits im Repository aktualisiert)

---

## Schritt 5: URL Scheme registrieren (fuer Shield Action)

1. Klicke auf **Target: iosApp**
2. Gehe zu **Info > URL Types**
3. Klicke **+**
4. Fuell aus:
   - **Identifier:** `com.flomks.pushup`
   - **URL Schemes:** `pushup`
5. Klicke **Save**

Damit kann der Shield-Button die PushUp App direkt oeffnen.

---

## Schritt 6: App Group in allen Targets pruefen

Stelle sicher, dass `group.com.flomks.pushup` in ALLEN fuenf Targets
unter **Signing & Capabilities > App Groups** eingetragen ist:
- iosApp (Haupt-App)
- ScreenTimeMonitor
- ShieldConfiguration
- ShieldAction
- DeviceActivityReport (neu)

---

## Schritt 7: Testen

**Wichtig:** Screen Time APIs funktionieren NUR auf echten Geraeten.
Der Simulator unterstuetzt FamilyControls nicht.

1. Baue die App auf einem echten iPhone
2. Gehe zu **Settings > Screen Time**
3. Tippe auf **Screen Time & App Blocking**
4. Tippe auf **Screen Time Permission** -- der System-Dialog erscheint
5. Bestatige die Berechtigung
6. Tippe auf **Select Apps to Block** -- der `FamilyActivityPicker` erscheint
7. Waehle einige Apps (z.B. Social Media Kategorie)
8. Gehe zurueck zum Dashboard -- die Screen Time Status Card erscheint
9. Starte ein Workout -- nach dem Workout wird das Guthaben erhoehen
10. Wenn das Guthaben auf 0 faellt, werden die Apps automatisch gesperrt
11. Im Stats-Tab > Screen Time siehst du jetzt Per-App-Nutzungsdaten

---

## Dateistruktur (aktualisiert)

```
iosApp/
├── iosApp/
│   ├── iosApp.entitlements          -- FamilyControls + App Groups
│   ├── Services/
│   │   └── ScreenTime/
│   │       ├── ScreenTimeManager.swift      -- Haupt-Service (Authorization, Blocking)
│   │       └── ScreenTimeUsageStore.swift   -- App Group Datenspeicher + PerAppUsageRecord
│   ├── Features/
│   │   ├── Settings/
│   │   │   └── ScreenTimeSettingsView.swift -- Settings-Screen fuer Screen Time
│   │   ├── Stats/
│   │   │   └── ScreenTime/
│   │   │       ├── ScreenTimeStatsView.swift       -- Vollbild-Statistiken
│   │   │       ├── ScreenTimeStatsInlineView.swift -- Inline im Stats-Tab
│   │   │       └── ScreenTimeAppUsageView.swift    -- Per-App-Nutzung (NEU)
│   │   └── Dashboard/
│   │       └── Components/
│   │           └── ScreenTimeStatusCard.swift -- Dashboard-Karte
│   └── Design/
│       └── Icons.swift              -- Screen Time Icons
│
├── ScreenTimeMonitor/               -- DeviceActivity Monitor Extension
│   ├── DeviceActivityMonitorExtension.swift  -- Reinstall-proof usage tracking
│   └── ScreenTimeMonitor.entitlements
│
├── ShieldConfiguration/             -- Shield Configuration Extension
│   ├── ShieldConfigurationExtension.swift
│   └── ShieldConfiguration.entitlements
│
├── ShieldAction/                    -- Shield Action Extension
│   ├── ShieldActionExtension.swift
│   └── ShieldAction.entitlements
│
└── DeviceActivityReport/            -- DeviceActivity Report Extension (NEU)
    ├── DeviceActivityReportExtension.swift  -- Per-App-Nutzung aus dem OS
    ├── DeviceActivityReport.entitlements
    └── Info.plist
```

---

## Reinstall-Schutz: Technische Erklaerung

### Das Problem

Wenn ein Nutzer die App deinstalliert und neu installiert, werden die
App Group UserDefaults geleert. Das bedeutet:
- `screentime.startOfDaySeconds` (Snapshot des Guthabens bei Tagesbeginn) ist weg
- `screentime.availableSeconds` (aktuelles Guthaben) ist weg

Wenn der Nutzer dann ein Workout macht und 30 Minuten verdient, wuerde
`startMonitoring` den Threshold auf 30 Minuten setzen -- obwohl der Nutzer
heute bereits 60 Minuten verbraucht hat.

### Die Loesung

Das iOS Screen Time System trackt die kumulative Nutzung seit Mitternacht
**unabhaengig von unserer App**. Die `DeviceActivityMonitorExtension` laeuft
in einem separaten Prozess und schreibt bei jedem Threshold-Event den Wert
`screentime.todaySystemUsageSeconds` in die App Group.

Dieser Wert wird beim Neustart der App gelesen und als autoritativer
"bereits heute verbraucht"-Offset verwendet:

```
cumulativeLimitSeconds = todaySystemUsageSeconds + availableSeconds
```

Beispiel nach Reinstall:
- Nutzer hat heute 60 Min verbraucht
- Reinstall: App Group wird geleert
- Nutzer verdient 30 Min durch Workout
- DB-Guthaben = 30 Min
- todaySystemUsageSeconds = 3600 (60 Min, vom Extension-Prozess)
- cumulativeLimitSeconds = 3600 + 1800 = 5400 (90 Min)
- System sperrt nach weiteren 30 Min -- korrekt!

### Prioritaet der Werte

1. `screentime.todaySystemUsageSeconds` -- vom OS getrackt, reinstall-proof
2. `screentime.startOfDaySeconds` -- Snapshot-Fallback, nur wenn kein OS-Wert

---

## Troubleshooting

### "Family Controls not available"
- Stelle sicher, dass das Geraet iOS 16+ hat
- Stelle sicher, dass die App auf einem echten Geraet laeuft (kein Simulator)
- Pruefe, ob `com.apple.developer.family-controls` im Entitlements-File steht

### FamilyActivityPicker zeigt sich nicht
- Die `Family Controls` Capability muss im Xcode-Target aktiviert sein
- Das Provisioning Profile muss die Family Controls Capability enthalten
- Regeneriere das Provisioning Profile nach dem Aktivieren der Capability

### Apps werden nicht gesperrt
- Pruefe, ob die `ManagedSettingsStore` im richtigen Kontext aufgerufen wird
- Die Extension muss die gleiche App Group wie die Haupt-App haben
- Stelle sicher, dass `FamilyActivitySelection` korrekt in der App Group gespeichert ist

### DeviceActivity Callbacks kommen nicht an
- Die Extension muss als separates Target in Xcode existieren
- Die Bundle ID muss `com.flomks.pushup.ScreenTimeMonitor` sein
- Pruefe, ob `DeviceActivityCenter.startMonitoring()` ohne Fehler aufgerufen wurde

### Per-App-Nutzung wird nicht angezeigt
- Die `DeviceActivityReport` Extension muss als separates Target existieren
- Bundle ID muss `com.flomks.pushup.DeviceActivityReport` sein
- Minimum Deployment Target muss iOS 16.4 sein
- Die Extension muss die gleiche App Group haben
- Per-App-Daten erscheinen erst nach dem ersten Threshold-Event
