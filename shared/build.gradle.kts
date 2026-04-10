import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.androidLibrary)
    alias(libs.plugins.kotlinSerialization)
    alias(libs.plugins.sqldelight)
}

kotlin {
    // Opt-in to stable expect/actual classes (currently in Beta -- suppresses the warning).
    // See: https://youtrack.jetbrains.com/issue/KT-61573
    compilerOptions {
        freeCompilerArgs.add("-Xexpect-actual-classes")
    }

    androidTarget {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_11)
        }
    }

    listOf(
        iosArm64(),
        iosSimulatorArm64(),
        iosX64(),
    ).forEach { iosTarget ->
        iosTarget.binaries.framework {
            baseName = "Shared"
            isStatic = true
        }
    }

    jvm()

    sourceSets {
        commonMain.dependencies {
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.datetime)
            implementation(libs.kotlinx.serialization.json)
            implementation(libs.sqldelight.runtime)
            implementation(libs.sqldelight.coroutines)
            implementation(libs.koin.core)
            // Ktor Client -- core + plugins (engine is platform-specific)
            implementation(libs.ktor.client.core)
            implementation(libs.ktor.client.contentNegotiation)
            implementation(libs.ktor.client.logging)
            implementation(libs.ktor.client.auth)
            implementation(libs.ktor.serialization.json)
        }
        commonTest.dependencies {
            implementation(libs.kotlin.test)
            implementation(libs.kotlinx.coroutines.test)
            implementation(libs.ktor.client.mock)
        }
        androidMain.dependencies {
            implementation(libs.sqldelight.driver.android)
            implementation(libs.koin.android)
            // Ktor Client engine for Android
            implementation(libs.ktor.client.okhttp)
            // Secure token storage (EncryptedSharedPreferences)
            implementation(libs.androidx.security.crypto)
        }
        iosMain.dependencies {
            implementation(libs.sqldelight.driver.native)
            // Ktor Client engine for iOS (Darwin)
            implementation(libs.ktor.client.darwin)
        }
        jvmMain.dependencies {
            implementation(libs.sqldelight.driver.jvm)
            // Ktor Client engine for JVM/Desktop
            implementation(libs.ktor.client.cio)
        }
        jvmTest.dependencies {
            // koin-test uses kotlin-reflect and is JVM-only; not available on Kotlin/Native
            implementation(libs.koin.test)
        }
    }
}

android {
    namespace = "com.flomks.sinura.shared"
    compileSdk = libs.versions.android.compileSdk.get().toInt()
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    defaultConfig {
        minSdk = libs.versions.android.minSdk.get().toInt()
    }
    lint {
        // The shared module has no AndroidManifest with permissions -- the app
        // module's manifest declares ACCESS_NETWORK_STATE. Lint cannot verify
        // this cross-module, so we suppress the false-positive here.
        disable += "MissingPermission"
    }
}

sqldelight {
    databases {
        create("SinuraDatabase") {
            packageName.set("com.sinura.db")
            schemaOutputDirectory.set(file("src/commonMain/sqldelight/migrations"))
            // Enable once migrations exist and a schema .db file has been generated
            // via `./gradlew :shared:generateCommonMainSinuraDatabaseSchema`
            verifyMigrations.set(false)
        }
    }
}
