package com.pushup.di

import android.content.Context
import com.flomks.pushup.db.AndroidDatabaseDriverFactory
import com.flomks.pushup.db.DatabaseDriverFactory
import com.pushup.data.storage.TokenStorage
import org.koin.android.ext.koin.androidContext
import org.koin.android.ext.koin.androidLogger
import org.koin.core.context.startKoin
import org.koin.core.logger.Level
import org.koin.core.module.Module
import org.koin.core.qualifier.named
import org.koin.dsl.module

/**
 * Android-specific Koin module.
 *
 * Provides:
 * - [AndroidDatabaseDriverFactory] as the platform [DatabaseDriverFactory] implementation.
 * - [TokenStorage] backed by [EncryptedSharedPreferences] for secure token persistence.
 *
 * Both bindings require the Android [Context] which is resolved from the Koin
 * Android context set up by [androidContext] in [initKoin].
 */
val androidModule = module {
    single<DatabaseDriverFactory> { AndroidDatabaseDriverFactory(context = androidContext()) }
    single { TokenStorage(context = androidContext()) }

    // Custom Ktor backend base URL -- hardcoded so it persists across builds
    // without requiring manual configuration or GitHub secrets.
    single<String>(named(BACKEND_BASE_URL)) { "https://pushup.weareo.fun" }
}

/**
 * Initialises Koin for the Android application.
 *
 * Call this function from your [android.app.Application.onCreate]:
 *
 * ```kotlin
 * class PushUpApplication : Application() {
 *     override fun onCreate() {
 *         super.onCreate()
 *         initKoin(this)
 *     }
 * }
 * ```
 *
 * Register the application class in `AndroidManifest.xml`:
 * ```xml
 * <application android:name=".PushUpApplication" ...>
 * ```
 *
 * @param context The application [Context] used to initialise the Android
 *   Koin extension and to create the SQLite driver.
 * @param isDebug When `true`, Koin logs at [Level.DEBUG] to surface binding
 *   warnings during development. Set to `false` (or `BuildConfig.DEBUG`) in
 *   production to suppress verbose output.
 */
fun initKoin(context: Context, isDebug: Boolean = false, vararg extraModules: Module) {
    startKoin {
        androidLogger(if (isDebug) Level.DEBUG else Level.ERROR)
        androidContext(context)
        modules(listOf(androidModule) + sharedModules + extraModules.toList())
    }
}
