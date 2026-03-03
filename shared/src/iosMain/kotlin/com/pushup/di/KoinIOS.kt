package com.pushup.di

import com.flomks.pushup.db.DatabaseDriverFactory
import com.flomks.pushup.db.IosDatabaseDriverFactory
import org.koin.core.KoinApplication
import org.koin.core.context.startKoin
import org.koin.dsl.module

/**
 * iOS-specific Koin module.
 *
 * Provides the [IosDatabaseDriverFactory] as the platform [DatabaseDriverFactory]
 * implementation. This binding is required by [databaseModule] in [AppModule.kt].
 */
val iosModule = module {
    single<DatabaseDriverFactory> { IosDatabaseDriverFactory() }
}

/**
 * Initialises Koin for the iOS application.
 *
 * Call this function from your Swift `AppDelegate` or `@main` entry point
 * **before** any Koin-managed dependency is accessed:
 *
 * ```swift
 * // AppDelegate.swift
 * KoinIOSKt.doInitKoin()
 * ```
 *
 * @return The [KoinApplication] instance, which can be used for further
 *   configuration or testing if needed.
 */
fun initKoin(): KoinApplication = startKoin {
    modules(iosModule + sharedModules)
}
