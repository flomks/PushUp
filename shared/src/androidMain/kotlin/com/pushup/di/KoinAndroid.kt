package com.pushup.di

import android.content.Context
import com.flomks.pushup.db.AndroidDatabaseDriverFactory
import com.flomks.pushup.db.DatabaseDriverFactory
import com.pushup.data.api.JwtTokenProvider
import com.pushup.data.storage.TokenStorage
import com.pushup.domain.repository.AuthRepository
import com.pushup.domain.usecase.sync.AndroidNetworkMonitor
import com.pushup.domain.usecase.sync.NetworkMonitor
import kotlinx.datetime.Clock
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
 * Provides all platform-specific bindings required by [sharedModules]:
 *
 * - [AndroidDatabaseDriverFactory] as the platform [DatabaseDriverFactory].
 * - [TokenStorage] backed by [EncryptedSharedPreferences] for secure token persistence.
 * - [AndroidNetworkMonitor] as the [NetworkMonitor] implementation.
 * - [JwtTokenProvider] that reads the stored access token from [TokenStorage].
 *   Throws [IllegalStateException] when the user is not authenticated, which
 *   prevents unauthenticated requests from being sent silently.
 * - [SUPABASE_URL] and [SUPABASE_ANON_KEY] injected via [BuildConfig] fields
 *   (set from `local.properties` at build time).
 * - [BACKEND_BASE_URL] hardcoded to the production server URL.
 * - [IS_DEBUG] set from [android.BuildConfig.DEBUG].
 *
 * All bindings that require the Android [Context] resolve it from the Koin
 * Android context set up by [androidContext] in [initKoin].
 */
fun androidModule(
    supabaseUrl: String,
    supabaseAnonKey: String,
    isDebug: Boolean,
) = module {
    // Platform database driver
    single<DatabaseDriverFactory> { AndroidDatabaseDriverFactory(context = androidContext()) }

    // Encrypted token storage (EncryptedSharedPreferences / Android Keystore)
    single { TokenStorage(context = androidContext()) }

    // Network connectivity monitor (ConnectivityManager, API 23+).
    single<NetworkMonitor>(named(NETWORK_MONITOR)) {
        AndroidNetworkMonitor(context = androidContext())
    }

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

    // Supabase project URL -- injected from local.properties via BuildConfig.
    single<String>(named(SUPABASE_URL)) { supabaseUrl }

    // Supabase anon (public) API key -- injected from local.properties via BuildConfig.
    single<String>(named(SUPABASE_ANON_KEY)) { supabaseAnonKey }

    // Custom Ktor backend base URL -- hardcoded so it persists across builds
    // without requiring manual configuration or GitHub secrets.
    single<String>(named(BACKEND_BASE_URL)) { "https://pushup.weareo.fun" }

    // HTTP debug logging flag.
    single<Boolean>(named(IS_DEBUG)) { isDebug }
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
 *         initKoin(
 *             context = this,
 *             supabaseUrl = BuildConfig.SUPABASE_URL,
 *             supabaseAnonKey = BuildConfig.SUPABASE_ANON_KEY,
 *             isDebug = BuildConfig.DEBUG,
 *         )
 *     }
 * }
 * ```
 *
 * Register the application class in `AndroidManifest.xml`:
 * ```xml
 * <application android:name=".PushUpApplication" ...>
 * ```
 *
 * @param context        The application [Context] used to initialise the Android
 *                       Koin extension and to create the SQLite driver.
 * @param supabaseUrl    Supabase project URL (from BuildConfig / local.properties).
 * @param supabaseAnonKey Supabase anon key (from BuildConfig / local.properties).
 * @param isDebug        When `true`, Koin logs at [Level.DEBUG] to surface binding
 *                       warnings during development.
 * @param extraModules   Additional Koin modules (e.g. the presentation module).
 */
fun initKoin(
    context: Context,
    supabaseUrl: String = "",
    supabaseAnonKey: String = "",
    isDebug: Boolean = false,
    vararg extraModules: Module,
) {
    startKoin {
        androidLogger(if (isDebug) Level.DEBUG else Level.ERROR)
        androidContext(context)
        modules(
            listOf(androidModule(supabaseUrl, supabaseAnonKey, isDebug)) +
                sharedModules +
                extraModules.toList()
        )
    }
}
