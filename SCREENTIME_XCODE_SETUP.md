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

## Schritt 3: Drei neue Extension Targets in Xcode erstellen

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
   `iosApp/ScreenTimeMonitor/ScreenTimeMonitorExtension.swift`
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

Stelle sicher, dass `group.com.flomks.pushup` in ALLEN vier Targets
unter **Signing & Capabilities > App Groups** eingetragen ist:
- iosApp (Haupt-App)
- ScreenTimeMonitor
- ShieldConfiguration
- ShieldAction

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

---

## Dateistruktur (neu hinzugefuegt)

```
iosApp/
├── iosApp/
│   ├── iosApp.entitlements          -- FamilyControls + App Groups hinzugefuegt
│   ├── Services/
│   │   └── ScreenTime/
│   │       ├── ScreenTimeManager.swift      -- Haupt-Service (Authorization, Blocking)
│   │       └── ScreenTimeUsageStore.swift   -- App Group Datenspeicher
│   ├── Features/
│   │   ├── Settings/
│   │   │   └── ScreenTimeSettingsView.swift -- Settings-Screen fuer Screen Time
│   │   ├── Stats/
│   │   │   └── ScreenTime/
│   │   │       ├── ScreenTimeStatsView.swift       -- Vollbild-Statistiken
│   │   │       └── ScreenTimeStatsInlineView.swift -- Inline im Stats-Tab
│   │   └── Dashboard/
│   │       └── Components/
│   │           └── ScreenTimeStatusCard.swift -- Dashboard-Karte
│   └── Design/
│       └── Icons.swift              -- Screen Time Icons hinzugefuegt
│
├── ScreenTimeMonitor/               -- DeviceActivity Monitor Extension
│   ├── ScreenTimeMonitorExtension.swift
│   └── ScreenTimeMonitor.entitlements
│
├── ShieldConfiguration/             -- Shield Configuration Extension
│   ├── ShieldConfigurationExtension.swift
│   └── ShieldConfiguration.entitlements
│
└── ShieldAction/                    -- Shield Action Extension
    ├── ShieldActionExtension.swift
    └── ShieldAction.entitlements
```

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
