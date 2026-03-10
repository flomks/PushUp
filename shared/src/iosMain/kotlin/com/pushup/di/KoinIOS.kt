package com.pushup.di

import com.flomks.pushup.db.DatabaseDriverFactory
import com.flomks.pushup.db.IosDatabaseDriverFactory
import com.pushup.data.api.JwtTokenProvider
import com.pushup.data.storage.TokenStorage
import com.pushup.domain.repository.AuthRepository
import com.pushup.domain.usecase.sync.IosNetworkMonitor
import com.pushup.domain.usecase.sync.NetworkMonitor
import kotlinx.datetime.Clock
import org.koin.core.context.startKoin
import org.koin.core.module.Module
import org.koin.core.qualifier.named
import org.koin.dsl.module
import platform.Foundation.NSBundle

/**
 * iOS-specific Koin module.
 *
 * Provides all platform-specific bindings required by [sharedModules]:
 *
 * - [IosDatabaseDriverFactory] as the platform [DatabaseDriverFactory].
 * - [TokenStorage] backed by the iOS Keychain for secure token persistence.
 * - [IosNetworkMonitor] as the [NetworkMonitor] implementation (NWPathMonitor).
 * - [JwtTokenProvider] that reads the stored access token from [TokenStorage].
 *   Throws [IllegalStateException] when the user is not authenticated, which
 *   prevents unauthenticated requests from being sent silently.
 * - [SUPABASE_URL] and [SUPABASE_PUBLISHABLE_KEY] read from the app bundle's
 *   Info.plist (keys: `SupabaseURL` and `SupabasePublishableKey`). These values
 *   are injected at build time via `Config.xcconfig` so they are never hardcoded
 *   in source code.
 * - [IS_DEBUG] hardcoded to `false`. Kotlin/Native has no `BuildConfig`
 *   equivalent. Enable verbose HTTP logging by overriding this binding in a
 *   debug-only Koin module if needed.
 */
val iosModule = module {
    // Platform database driver
    single<DatabaseDriverFactory> { IosDatabaseDriverFactory() }

    // Keychain-backed token storage
    single { TokenStorage() }

    // Network connectivity monitor (NWPathMonitor, iOS 12+).
    // Bound as a singleton for the application lifetime — the monitor runs
    // continuously and updates [connected] on a background dispatch queue.
    single<NetworkMonitor>(named(NETWORK_MONITOR)) { IosNetworkMonitor() }

    // JWT token provider: reads the stored access token from TokenStorage.
    //
    // Automatically refreshes the token when it is expired or within a
    // 60-second buffer window before expiry. This prevents 401 errors caused
    // by sending an expired Supabase JWT to the backend.
    //
    // Throws IllegalStateException when the user is not authenticated.
    single<JwtTokenProvider>(named(JWT_TOKEN_PROVIDER)) {
        val storage = get<TokenStorage>()
        val authRepository = get<AuthRepository>()
        JwtTokenProvider {
            val token = storage.load()
                ?: error(
                    "JwtTokenProvider: no authenticated session found. " +
                        "Call LoginWithEmailUseCase or a social login use case first."
                )
            // Refresh proactively if the token expires within 60 seconds.
            val nowSeconds = Clock.System.now().epochSeconds
            val isExpiredOrExpiringSoon = token.expiresAt - nowSeconds < 60L
            if (isExpiredOrExpiringSoon) {
                // refreshToken() stores the new token in TokenStorage and returns it.
                // If the refresh token itself is expired, this throws AuthException.SessionExpired
                // which will propagate as an error to the caller (correct behaviour).
                authRepository.refreshToken().accessToken
            } else {
                token.accessToken
            }
        }
    }

    // Supabase project URL — read from Info.plist key "SupabaseURL".
    // Set via SUPABASE_URL in Config.xcconfig which is injected into Info.plist
    // as INFOPLIST_KEY_SupabaseURL at build time.
    single<String>(named(SUPABASE_URL)) {
        NSBundle.mainBundle.objectForInfoDictionaryKey("SupabaseURL") as? String
            ?: ""
    }

    // Supabase publishable (public) API key — read from Info.plist key "SupabasePublishableKey".
    // Set via SUPABASE_PUBLISHABLE_KEY in Config.xcconfig.
    single<String>(named(SUPABASE_PUBLISHABLE_KEY)) {
        NSBundle.mainBundle.objectForInfoDictionaryKey("SupabasePublishableKey") as? String
            ?: ""
    }

    // Custom Ktor backend base URL — read from Info.plist key "BackendBaseURL".
    // Falls back to empty string when not configured (offline-only mode).
    single<String>(named(BACKEND_BASE_URL)) {
        NSBundle.mainBundle.objectForInfoDictionaryKey("BackendBaseURL") as? String
            ?: ""
    }

    // HTTP debug logging flag.
    // Kotlin/Native has no BuildConfig equivalent; hardcoded to false.
    // To enable verbose logging in development, override this binding in a
    // debug-only module passed to startKoin alongside iosModule.
    single<Boolean>(named(IS_DEBUG)) { false }
}

/**
 * Initialises Koin for the iOS application with optional extra modules.
 *
 * Prefer calling the no-argument [initKoin] overload from Swift, which maps
 * to `KoinIOSKt.doInitKoin()` with no parameters. Use this overload only
 * when you need to inject additional test or debug modules alongside the
 * standard iOS and shared modules.
 *
 * **Note on `vararg` and Swift interop:** Kotlin `vararg` parameters are
 * exposed to Swift as `KotlinArray<T>`, which is a required (non-optional)
 * parameter. Calling this overload from Swift therefore requires an explicit
 * array argument. The no-argument [initKoin] overload below avoids this
 * friction for the common case.
 *
 * @param extraModules Additional Koin modules to load alongside [iosModule]
 *   and [sharedModules]. Useful for injecting test doubles or feature flags.
 */
fun initKoin(vararg extraModules: Module) {
    startKoin {
        modules(listOf(iosModule) + sharedModules + extraModules.toList())
    }
}

/**
 * Initialises Koin for the iOS application.
 *
 * This is the primary entry point for Swift callers. It maps to
 * `KoinIOSKt.doInitKoin()` in Swift with **no arguments**, avoiding the
 * `KotlinArray` parameter that Kotlin's `vararg` produces in the Swift bridge.
 *
 * Call this from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
 * **before** any Koin-managed dependency is accessed:
 *
 * ```swift
 * final class AppDelegate: NSObject, UIApplicationDelegate {
 *     func application(
 *         _ application: UIApplication,
 *         didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
 *     ) -> Bool {
 *         KoinIOSKt.doInitKoin()
 *         return true
 *     }
 * }
 * ```
 *
 * Returns `Unit` (mapped to `Void` in Swift) to keep the Swift API surface
 * clean — callers have no use for the internal `KoinApplication` object.
 */
fun initKoin() {
    startKoin {
        modules(listOf(iosModule) + sharedModules)
    }
}
