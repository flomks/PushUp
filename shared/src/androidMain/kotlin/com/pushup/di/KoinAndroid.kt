package com.pushup.di

import android.content.Context
import com.flomks.pushup.db.AndroidDatabaseDriverFactory
import com.flomks.pushup.db.DatabaseDriverFactory
import org.koin.android.ext.koin.androidContext
import org.koin.android.ext.koin.androidLogger
import org.koin.core.KoinApplication
import org.koin.core.context.startKoin
import org.koin.core.logger.Level
import org.koin.dsl.module

/**
 * Android-specific Koin module.
 *
 * Provides the [AndroidDatabaseDriverFactory] as the platform [DatabaseDriverFactory]
 * implementation. This binding is required by [databaseModule] in [AppModule.kt].
 *
 * The [Context] is resolved from the Koin Android context that is set up
 * by [androidContext] in [initKoin].
 */
val androidModule = module {
    single<DatabaseDriverFactory> { AndroidDatabaseDriverFactory(context = androidContext()) }
}

/**
 * Initialises Koin for the Android application.
 *
 * Call this function from your [android.app.Application.onCreate]:
 *
 * ```kotlin
 * class MyApplication : Application() {
 *     override fun onCreate() {
 *         super.onCreate()
 *         initKoin(this)
 *     }
 * }
 * ```
 *
 * @param context The application [Context] used to initialise the Android
 *   Koin extension and to create the SQLite driver.
 * @return The [KoinApplication] instance for optional further configuration.
 */
fun initKoin(context: Context): KoinApplication = startKoin {
    androidLogger(Level.ERROR)
    androidContext(context)
    modules(androidModule + sharedModules)
}
