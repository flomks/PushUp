package com.pushup.di

import com.flomks.pushup.db.DatabaseDriverFactory
import com.flomks.pushup.db.IosDatabaseDriverFactory
import com.pushup.data.api.JwtTokenProvider
import com.pushup.data.storage.TokenStorage
import com.pushup.domain.usecase.sync.IosNetworkMonitor
import com.pushup.domain.usecase.sync.NetworkMonitor
import org.koin.core.context.startKoin
import org.koin.core.qualifier.named
import org.koin.dsl.module

/**
 * iOS-specific Koin module.
 *
 * Provides:
 * - [IosDatabaseDriverFactory] as the platform [DatabaseDriverFactory] implementation.
 * - [TokenStorage] backed by the iOS Keychain for secure token persistence.
 * - [IosNetworkMonitor] as the [NetworkMonitor] implementation.
 * - Placeholder named-string bindings for [SUPABASE_URL], [SUPABASE_ANON_KEY],
 *   [BACKEND_BASE_URL], and [JWT_TOKEN_PROVIDER] so that [apiModule] can be
 *   loaded without crashing at startup. Replace these with real values once
 *   the backend integration is configured (Task 3.x).
 * - [IS_DEBUG] flag set to `true` in debug builds.
 */
val iosModule = module {
    // Platform database driver
    single<DatabaseDriverFactory> { IosDatabaseDriverFactory() }

    // Keychain-backed token storage
    single { TokenStorage() }

    // Network connectivity monitor (NWPathMonitor)
    single<NetworkMonitor>(named(NETWORK_MONITOR)) { IosNetworkMonitor() }

    // JWT token provider: reads the stored token from TokenStorage.
    // Returns an empty string when no token is present (unauthenticated state).
    // Replace with a real Supabase Auth session provider in Task 3.x.
    single<JwtTokenProvider>(named(JWT_TOKEN_PROVIDER)) {
        val storage = get<TokenStorage>()
        JwtTokenProvider { storage.load()?.accessToken ?: "" }
    }

    // Supabase project URL.
    // Replace with the real project URL from your Supabase dashboard.
    // Example: "https://<ref>.supabase.co"
    single<String>(named(SUPABASE_URL)) { "" }

    // Supabase anon (public) API key.
    // Replace with the real anon key from your Supabase dashboard.
    single<String>(named(SUPABASE_ANON_KEY)) { "" }

    // Custom Ktor backend base URL.
    // Replace with the real backend URL once deployed.
    single<String>(named(BACKEND_BASE_URL)) { "" }

    // Debug flag: enables verbose HTTP logging in debug builds.
    single<Boolean>(named(IS_DEBUG)) {
        // Kotlin/Native does not have a BuildConfig equivalent.
        // Set to false for production; override in a debug-specific module if needed.
        false
    }
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
