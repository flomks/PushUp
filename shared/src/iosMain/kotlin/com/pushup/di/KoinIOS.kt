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
 * Provides all platform-specific bindings required by [sharedModules]:
 *
 * - [IosDatabaseDriverFactory] as the platform [DatabaseDriverFactory].
 * - [TokenStorage] backed by the iOS Keychain for secure token persistence.
 * - [IosNetworkMonitor] as the [NetworkMonitor] implementation (NWPathMonitor).
 * - [JwtTokenProvider] that reads the stored access token from [TokenStorage].
 *   Throws [IllegalStateException] when the user is not authenticated, which
 *   prevents unauthenticated requests from being sent silently.
 * - Placeholder named-string bindings for [SUPABASE_URL], [SUPABASE_ANON_KEY],
 *   and [BACKEND_BASE_URL]. Replace these with real values once the backend
 *   integration is configured (Task 3.x). The app will start and the local
 *   (offline) feature set will work; any network call will fail gracefully
 *   with a Ktor connection error rather than a crash.
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
    // Throws IllegalStateException when the user is not authenticated.
    // This is intentional: callers that invoke authenticated API endpoints
    // without a valid session should receive an explicit error rather than
    // silently sending an empty Bearer token to the backend.
    //
    // Replace with a Supabase Auth session provider in Task 3.x once the
    // auth flow is implemented.
    single<JwtTokenProvider>(named(JWT_TOKEN_PROVIDER)) {
        val storage = get<TokenStorage>()
        JwtTokenProvider {
            storage.load()?.accessToken
                ?: error(
                    "JwtTokenProvider: no authenticated session found. " +
                        "Call LoginWithEmailUseCase or a social login use case first."
                )
        }
    }

    // Supabase project URL.
    // Replace with the real project URL from your Supabase dashboard:
    //   "https://<ref>.supabase.co"
    single<String>(named(SUPABASE_URL)) { "" }

    // Supabase anon (public) API key.
    // Replace with the real anon key from your Supabase dashboard.
    single<String>(named(SUPABASE_ANON_KEY)) { "" }

    // Custom Ktor backend base URL.
    // Replace with the real backend URL once deployed.
    single<String>(named(BACKEND_BASE_URL)) { "" }

    // HTTP debug logging flag.
    // Kotlin/Native has no BuildConfig equivalent; hardcoded to false.
    // To enable verbose logging in development, override this binding in a
    // debug-only module passed to startKoin alongside iosModule.
    single<Boolean>(named(IS_DEBUG)) { false }
}

/**
 * Initialises Koin for the iOS application.
 *
 * Call this function from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
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
 *
 * @main
 * struct PushUpApp: App {
 *     @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
 *     var body: some Scene { WindowGroup { ContentView() } }
 * }
 * ```
 *
 * Returns `Unit` (mapped to `Void` in Swift) to keep the Swift API surface
 * clean — callers have no use for the internal `KoinApplication` object.
 */
fun initKoin() {
    startKoin {
        modules(iosModule + sharedModules)
    }
}
