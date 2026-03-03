# PushUp

[![CI](https://github.com/flomks/PushUp/actions/workflows/ci.yml/badge.svg)](https://github.com/flomks/PushUp/actions/workflows/ci.yml)

Tracke deine Liegestuetze per Kamera und verdiene dir Screen-Time.

**Kernprinzip:** Erst bewegen, dann konsumieren.

## Tech-Stack

| Komponente | Technologie |
|---|---|
| Shared Core | Kotlin Multiplatform (KMP) |
| iOS App | SwiftUI + Apple Vision Framework |
| Android App | Jetpack Compose + ML Kit |
| Lokale Datenbank | SQLDelight |

## Projektstruktur

```
PushUp/
├── shared/              # KMP Shared Module (commonMain, iosMain, androidMain, jvmMain)
├── composeApp/          # Compose Multiplatform App (Android + Desktop)
├── iosApp/              # Native iOS App (SwiftUI)
├── gradle/              # Gradle Wrapper und Version Catalog
├── build.gradle.kts     # Root Build-Konfiguration
└── settings.gradle.kts  # Projekt-Settings
```

## Voraussetzungen

- **JDK 21+** (LTS, verwendet in CI)
- **Android SDK** (compileSdk 36, minSdk 24)
- **Xcode 15+** (fuer iOS-Builds)
- **Kotlin 2.3.0** (wird ueber Gradle Wrapper verwaltet)

## Build-Befehle

```bash
# Gesamtes Projekt bauen (ohne iOS/Android-spezifische Targets)
./gradlew build

# Nur shared-Modul bauen
./gradlew :shared:build

# Tests ausfuehren (alle Targets)
./gradlew check

# Nur shared-Modul Tests (JVM)
./gradlew :shared:jvmTest

# Nur shared-Modul Tests (alle Targets)
./gradlew :shared:allTests

# Clean Build
./gradlew clean build

# Gradle-Version pruefen
./gradlew --version
```

## Abhaengigkeiten (Shared Module)

| Library | Version | Zweck |
|---|---|---|
| Kotlin | 2.3.0 | Sprache und Compiler |
| kotlinx-coroutines | 1.10.2 | Asynchrone Programmierung |
| kotlinx-datetime | 0.6.2 | Plattformunabhaengige Datums-/Zeitoperationen |
| kotlinx-serialization | 1.8.1 | JSON-Serialisierung |

## Status

Projekt befindet sich in Phase 1 (Projekt-Setup und Core-Logik). Siehe [PROJECT_PLAN.md](./PROJECT_PLAN.md) fuer den vollstaendigen Projektplan.
