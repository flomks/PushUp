package com.pushup.di

import com.flomks.pushup.db.DatabaseDriverFactory
import com.flomks.pushup.db.IosDatabaseDriverFactory
import com.pushup.data.storage.TokenStorage
import org.koin.core.context.startKoin
import org.koin.dsl.module

/**
 * iOS-specific Koin module.
 *
 * Provides:
 * - [IosDatabaseDriverFactory] as the platform [DatabaseDriverFactory] implementation.
 * - [TokenStorage] backed by the iOS Keychain for secure token persistence.
 */
val iosModule = module {
    single<DatabaseDriverFactory> { IosDatabaseDriverFactory() }
    single { TokenStorage() }
}

/**
 * Initialises Koin for the iOS application.
 *
 * Call this function from your Swift `@main` entry point or `AppDelegate`
 * **before** any Koin-managed dependency is accessed:
 *
 * ```swift
 * @main
 * struct PushUpApp: App {
 *     init() {
 *         KoinIOSKt.doInitKoin()
 *     }
 *     var body: some Scene { ... }
 * }
 * ```
 *
 * Returns `Unit` (mapped to `Void` in Swift) to keep the Swift API surface
 * clean -- callers have no use for the internal `KoinApplication` object.
 */
fun initKoin() {
    startKoin {
        modules(iosModule + sharedModules)
    }
}
