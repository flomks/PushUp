package com.pushup.di

import com.flomks.pushup.db.DatabaseDriverFactory
import com.pushup.data.api.JwtTokenProvider
import com.pushup.data.api.KtorApiClient
import com.pushup.data.api.SupabaseClient
import com.pushup.data.api.createHttpClient
import com.pushup.data.repository.PushUpRecordRepositoryImpl
import com.pushup.data.repository.StatsRepositoryImpl
import com.pushup.data.repository.TimeCreditRepositoryImpl
import com.pushup.data.repository.UserRepositoryImpl
import com.pushup.data.repository.UserSettingsRepositoryImpl
import com.pushup.data.repository.WorkoutSessionRepositoryImpl
import com.pushup.db.PushUpDatabase
import com.pushup.domain.repository.PushUpRecordRepository
import com.pushup.domain.repository.StatsRepository
import com.pushup.domain.repository.TimeCreditRepository
import com.pushup.domain.repository.UserRepository
import com.pushup.domain.repository.UserSettingsRepository
import com.pushup.domain.repository.WorkoutSessionRepository
import com.pushup.domain.usecase.DefaultIdGenerator
import com.pushup.domain.usecase.FinishWorkoutUseCase
import com.pushup.domain.usecase.GetDailyStatsUseCase
import com.pushup.domain.usecase.GetMonthlyStatsUseCase
import com.pushup.domain.usecase.GetOrCreateLocalUserUseCase
import com.pushup.domain.usecase.GetTimeCreditUseCase
import com.pushup.domain.usecase.GetTotalStatsUseCase
import com.pushup.domain.usecase.GetUserSettingsUseCase
import com.pushup.domain.usecase.GetWeeklyStatsUseCase
import com.pushup.domain.usecase.IdGenerator
import com.pushup.domain.usecase.RecordPushUpUseCase
import com.pushup.domain.usecase.SpendTimeCreditUseCase
import com.pushup.domain.usecase.StartWorkoutUseCase
import com.pushup.domain.usecase.UpdateUserSettingsUseCase
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.datetime.Clock
import org.koin.core.module.Module
import org.koin.core.qualifier.named
import org.koin.dsl.module

/**
 * Named Koin qualifier for the coroutine dispatcher used by all database-backed
 * repositories.
 *
 * Binding the dispatcher under a named qualifier (rather than hardcoding it
 * inside each repository factory) allows tests to override it with a
 * [kotlinx.coroutines.test.TestDispatcher] via `KoinTestHelper.startTestKoin`,
 * giving full control over coroutine execution in unit tests.
 *
 * Production value: [Dispatchers.Default] -- the correct KMP-safe choice.
 * [Dispatchers.IO] does not exist on Kotlin/Native (iOS) and must not be used
 * in shared code.
 */
const val DB_DISPATCHER = "db_dispatcher"

/**
 * Infrastructure module: binds cross-cutting singletons that multiple layers depend on.
 *
 * - [Clock]: used by use-cases and repositories for timestamps. Override with a
 *   fixed clock in tests for deterministic results.
 * - [IdGenerator]: used by use-cases to generate unique entity IDs.
 * - DB [CoroutineDispatcher] (named [DB_DISPATCHER]): used by all repositories.
 *   Override with a [kotlinx.coroutines.test.TestDispatcher] in tests.
 */
val infrastructureModule: Module = module {
    single<Clock> { Clock.System }
    single<IdGenerator> { DefaultIdGenerator }
    single<CoroutineDispatcher>(named(DB_DISPATCHER)) { Dispatchers.Default }
}

/**
 * Database module: constructs the [PushUpDatabase] singleton from the
 * platform-provided [DatabaseDriverFactory].
 *
 * The [DatabaseDriverFactory] must be bound by the platform-specific module
 * (see KoinAndroid.kt / KoinIOS.kt / KoinJVM.kt) before this module is used.
 */
val databaseModule: Module = module {
    single<PushUpDatabase> {
        PushUpDatabase(get<DatabaseDriverFactory>().createDriver())
    }
}

/**
 * Repository module: binds all repository implementations as **singletons**.
 *
 * Each implementation is bound to its corresponding interface so that
 * use-cases and other consumers depend only on the abstraction.
 *
 * The DB dispatcher is resolved by name ([DB_DISPATCHER]) so that tests can
 * substitute a [kotlinx.coroutines.test.TestDispatcher] without touching the
 * production wiring.
 */
val repositoryModule: Module = module {
    single<UserRepository> {
        UserRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
        )
    }

    single<WorkoutSessionRepository> {
        WorkoutSessionRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
            clock = get(),
        )
    }

    single<PushUpRecordRepository> {
        PushUpRecordRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
        )
    }

    single<TimeCreditRepository> {
        TimeCreditRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
            clock = get(),
        )
    }

    single<UserSettingsRepository> {
        UserSettingsRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
        )
    }

    single<StatsRepository> {
        StatsRepositoryImpl(
            database = get(),
            timeCreditRepository = get(),
            dispatcher = get(named(DB_DISPATCHER)),
            clock = get(),
        )
    }
}

/**
 * Use-case module: binds all use-cases as **factories**.
 *
 * A new instance is created on every injection, which keeps use-cases
 * stateless and easy to test in isolation.
 *
 * [Clock] and [IdGenerator] are resolved from Koin so that tests can
 * substitute controlled implementations via `KoinTestHelper.startTestKoin`.
 */
val useCaseModule: Module = module {
    factory { GetOrCreateLocalUserUseCase(userRepository = get(), clock = get(), idGenerator = get()) }
    factory { StartWorkoutUseCase(sessionRepository = get(), clock = get(), idGenerator = get()) }
    factory {
        RecordPushUpUseCase(
            sessionRepository = get(),
            recordRepository = get(),
            clock = get(),
            idGenerator = get(),
        )
    }
    factory {
        FinishWorkoutUseCase(
            sessionRepository = get(),
            recordRepository = get(),
            timeCreditRepository = get(),
            settingsRepository = get(),
            clock = get(),
        )
    }
    factory { GetTimeCreditUseCase(timeCreditRepository = get(), clock = get()) }
    factory { SpendTimeCreditUseCase(timeCreditRepository = get(), clock = get()) }
    factory { GetUserSettingsUseCase(settingsRepository = get()) }
    factory { UpdateUserSettingsUseCase(settingsRepository = get()) }
    factory { GetDailyStatsUseCase(statsRepository = get()) }
    factory { GetWeeklyStatsUseCase(statsRepository = get()) }
    factory { GetMonthlyStatsUseCase(statsRepository = get()) }
    factory { GetTotalStatsUseCase(statsRepository = get()) }
}

/**
 * Named Koin qualifier for the Supabase project URL.
 *
 * Bind this in your platform-specific module (or override in tests):
 * ```kotlin
 * single<String>(named(SUPABASE_URL)) { "https://<ref>.supabase.co" }
 * ```
 */
const val SUPABASE_URL = "supabase_url"

/**
 * Named Koin qualifier for the Supabase anon (public) API key.
 *
 * Bind this in your platform-specific module (or override in tests):
 * ```kotlin
 * single<String>(named(SUPABASE_ANON_KEY)) { BuildConfig.SUPABASE_ANON_KEY }
 * ```
 */
const val SUPABASE_ANON_KEY = "supabase_anon_key"

/**
 * Named Koin qualifier for the Ktor backend base URL.
 *
 * Bind this in your platform-specific module (or override in tests):
 * ```kotlin
 * single<String>(named(BACKEND_BASE_URL)) { "https://api.pushup.com" }
 * ```
 */
const val BACKEND_BASE_URL = "backend_base_url"

/**
 * Named Koin qualifier for the [JwtTokenProvider] binding.
 *
 * Bind a [JwtTokenProvider] implementation in your platform-specific module:
 * ```kotlin
 * single<JwtTokenProvider>(named(JWT_TOKEN_PROVIDER)) {
 *     JwtTokenProvider { supabaseAuth.currentSession?.accessToken ?: error("Not authenticated") }
 * }
 * ```
 */
const val JWT_TOKEN_PROVIDER = "jwt_token_provider"

/**
 * API module: binds the [io.ktor.client.HttpClient], [SupabaseClient], and
 * [KtorApiClient] as **singletons**.
 *
 * Requires the following named bindings to be provided by the platform-specific
 * module before this module is used:
 * - `String` named [SUPABASE_URL]
 * - `String` named [SUPABASE_ANON_KEY]
 * - `String` named [BACKEND_BASE_URL]
 * - [JwtTokenProvider] named [JWT_TOKEN_PROVIDER]
 *
 * In development / testing, these can be provided via a test module that
 * supplies mock values.
 */
val apiModule: Module = module {
    // Shared HttpClient -- one instance for both API clients
    single {
        createHttpClient(isDebug = false)
    }

    // Supabase REST API client
    single {
        val tokenProvider: JwtTokenProvider = get(named(JWT_TOKEN_PROVIDER))
        SupabaseClient(
            httpClient = get(),
            supabaseUrl = get(named(SUPABASE_URL)),
            supabaseAnonKey = get(named(SUPABASE_ANON_KEY)),
            tokenProvider = { tokenProvider.getToken() },
            clock = get(),
        )
    }

    // Custom Ktor backend client
    single {
        val tokenProvider: JwtTokenProvider = get(named(JWT_TOKEN_PROVIDER))
        KtorApiClient(
            httpClient = get(),
            backendBaseUrl = get(named(BACKEND_BASE_URL)),
            tokenProvider = { tokenProvider.getToken() },
        )
    }
}

/**
 * Aggregated list of all shared modules.
 *
 * Platform entry points (`initKoin()` on Android / iOS / JVM) should pass this
 * list together with their platform-specific module to `startKoin`.
 *
 * Note: [apiModule] is included here but requires the platform-specific module
 * to provide the named string bindings ([SUPABASE_URL], [SUPABASE_ANON_KEY],
 * [BACKEND_BASE_URL]) and the JWT token provider ([JWT_TOKEN_PROVIDER]).
 * If you are not yet integrating the API layer, you can exclude [apiModule]
 * from the list and add it later.
 */
val sharedModules: List<Module> = listOf(
    infrastructureModule,
    databaseModule,
    repositoryModule,
    useCaseModule,
    apiModule,
)
