package com.sinura.di

import com.flomks.sinura.db.DatabaseDriverFactory
import com.sinura.data.api.JwtTokenProvider
import com.sinura.data.api.KtorApiClient
import com.sinura.data.api.AuthClient
import com.sinura.data.api.SupabaseAuthClient
import com.sinura.data.api.SupabaseClient
import com.sinura.data.api.createHttpClient
import com.sinura.data.repository.ActivityStatsRepositoryImpl
import com.sinura.data.repository.AuthRepositoryImpl
import com.sinura.data.repository.JoggingSessionRepositoryImpl
import com.sinura.data.repository.JoggingPlaybackEntryRepositoryImpl
import com.sinura.data.repository.JoggingSegmentRepositoryImpl
import com.sinura.data.repository.ExerciseLevelRepositoryImpl
import com.sinura.data.repository.LevelRepositoryImpl
import com.sinura.data.repository.LiveRunPresenceRepositoryImpl
import com.sinura.data.repository.LiveRunSessionRepositoryImpl
import com.sinura.data.repository.PushUpRecordRepositoryImpl
import com.sinura.data.repository.RoutePointRepositoryImpl
import com.sinura.data.repository.RunEventRepositoryImpl
import com.sinura.data.repository.RunXpAwardRepositoryImpl
import com.sinura.data.repository.StatsRepositoryImpl
import com.sinura.data.repository.DailyCreditSnapshotRepositoryImpl
import com.sinura.data.repository.TimeCreditRepositoryImpl
import com.sinura.data.repository.UserRepositoryImpl
import com.sinura.data.repository.UserSettingsRepositoryImpl
import com.sinura.data.repository.WorkoutSessionRepositoryImpl
import com.sinura.db.SinuraDatabase
import com.sinura.domain.repository.ActivityStatsRepository
import com.sinura.domain.repository.AuthRepository
import com.sinura.domain.repository.JoggingSessionRepository
import com.sinura.domain.repository.JoggingPlaybackEntryRepository
import com.sinura.domain.repository.JoggingSegmentRepository
import com.sinura.domain.repository.ExerciseLevelRepository
import com.sinura.domain.repository.LevelRepository
import com.sinura.domain.repository.LiveRunPresenceRepository
import com.sinura.domain.repository.LiveRunSessionRepository
import com.sinura.domain.repository.PushUpRecordRepository
import com.sinura.domain.repository.RoutePointRepository
import com.sinura.domain.repository.RunEventRepository
import com.sinura.domain.repository.RunXpAwardRepository
import com.sinura.domain.repository.StatsRepository
import com.sinura.domain.repository.DailyCreditSnapshotRepository
import com.sinura.domain.repository.TimeCreditRepository
import com.sinura.domain.repository.UserRepository
import com.sinura.domain.repository.UserSettingsRepository
import com.sinura.domain.repository.WorkoutSessionRepository
import com.sinura.domain.usecase.ApplyDailyResetUseCase
import com.sinura.domain.usecase.AwardSocialRunXpUseCase
import com.sinura.domain.usecase.AwardWorkoutXpUseCase
import com.sinura.domain.usecase.GetActivityStreakUseCase
import com.sinura.domain.usecase.GetMonthlyActivityUseCase
import com.sinura.domain.usecase.DefaultIdGenerator
import com.sinura.domain.usecase.DeleteRunEventUseCase
import com.sinura.domain.usecase.FinishWorkoutUseCase
import com.sinura.domain.usecase.FinishLiveRunSessionUseCase
import com.sinura.domain.usecase.GetCreditBreakdownUseCase
import com.sinura.domain.usecase.GetExerciseLevelsUseCase
import com.sinura.domain.usecase.GetDailyStatsUseCase
import com.sinura.domain.usecase.GetMonthlyStatsUseCase
import com.sinura.domain.usecase.GetOrCreateLocalUserUseCase
import com.sinura.domain.usecase.GetJoggingSegmentsUseCase
import com.sinura.domain.usecase.GetJoggingPlaybackEntriesUseCase
import com.sinura.domain.usecase.GetUpcomingRunEventsUseCase
import com.sinura.domain.usecase.GetTimeCreditUseCase
import com.sinura.domain.usecase.GetTotalStatsUseCase
import com.sinura.domain.usecase.GetUserLevelUseCase
import com.sinura.domain.usecase.GetUserSettingsUseCase
import com.sinura.domain.usecase.GetWeeklyStatsUseCase
import com.sinura.domain.usecase.IdGenerator
import com.sinura.domain.usecase.FinishJoggingUseCase
import com.sinura.domain.usecase.JoinLiveRunSessionUseCase
import com.sinura.domain.usecase.LiveJoggingSessionManager
import com.sinura.domain.usecase.LeaveRunEventUseCase
import com.sinura.domain.usecase.LeaveLiveRunSessionUseCase
import com.sinura.domain.usecase.ObserveFriendsActiveRunsUseCase
import com.sinura.domain.usecase.ObserveLiveRunSessionUseCase
import com.sinura.domain.usecase.RecordPushUpUseCase
import com.sinura.domain.usecase.RecordRoutePointUseCase
import com.sinura.domain.usecase.CreateRunEventUseCase
import com.sinura.domain.usecase.RespondToRunEventUseCase
import com.sinura.domain.usecase.SpendTimeCreditUseCase
import com.sinura.domain.usecase.StartLiveRunSessionUseCase
import com.sinura.domain.usecase.StartJoggingUseCase
import com.sinura.domain.usecase.SaveJoggingSegmentsUseCase
import com.sinura.domain.usecase.SaveJoggingPlaybackEntriesUseCase
import com.sinura.domain.usecase.StartWorkoutUseCase
import com.sinura.domain.usecase.UpdateLiveRunPresenceUseCase
import com.sinura.domain.usecase.UpdateUserSettingsUseCase
import com.sinura.domain.usecase.auth.GetCurrentUserUseCase
import com.sinura.domain.usecase.auth.LoginWithAppleUseCase
import com.sinura.domain.usecase.auth.LoginWithEmailUseCase
import com.sinura.domain.usecase.auth.LoginWithGoogleUseCase
import com.sinura.domain.usecase.auth.LogoutUseCase
import com.sinura.domain.usecase.auth.RefreshTokenUseCase
import com.sinura.domain.usecase.auth.RegisterWithEmailUseCase
import com.sinura.data.api.CloudSyncApi
import com.sinura.data.api.FriendCodeApiClient
import com.sinura.data.api.FriendshipApiClient
import com.sinura.data.repository.FriendCodeRepositoryImpl
import com.sinura.data.repository.FriendshipRepositoryImpl
import com.sinura.domain.repository.FriendCodeRepository
import com.sinura.domain.repository.FriendshipRepository
import com.sinura.domain.usecase.sync.NetworkMonitor
import com.sinura.domain.usecase.sync.SyncFromCloudUseCase
import com.sinura.domain.usecase.sync.UserSettingsDashboardSyncUseCase
import com.sinura.domain.usecase.sync.SyncJoggingUseCase
import com.sinura.domain.usecase.sync.SyncExerciseLevelsUseCase
import com.sinura.domain.usecase.sync.SyncLevelUseCase
import com.sinura.domain.usecase.sync.SyncManager
import com.sinura.domain.usecase.sync.SyncTimeCreditUseCase
import com.sinura.domain.usecase.sync.SyncWorkoutsUseCase
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
 * Database module: constructs the [SinuraDatabase] singleton from the
 * platform-provided [DatabaseDriverFactory].
 *
 * The [DatabaseDriverFactory] must be bound by the platform-specific module
 * (see KoinAndroid.kt / KoinIOS.kt / KoinJVM.kt) before this module is used.
 */
val databaseModule: Module = module {
    single<SinuraDatabase> {
        SinuraDatabase(get<DatabaseDriverFactory>().createDriver())
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
            cloudSyncApi = getOrNull<CloudSyncApi>(),
            networkMonitor = getOrNull<NetworkMonitor>(named(NETWORK_MONITOR)),
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
            cloudSyncApi = getOrNull<CloudSyncApi>(),
            networkMonitor = getOrNull<NetworkMonitor>(named(NETWORK_MONITOR)),
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
            ktorApiClient = getOrNull<KtorApiClient>(),
            networkMonitor = getOrNull<NetworkMonitor>(named(NETWORK_MONITOR)),
        )
    }

    single<AuthRepository> {
        AuthRepositoryImpl(
            authClient = get(),
            tokenStorage = get(),
            userRepository = get(),
            database = get(),
            clock = get(),
            dispatcher = get(named(DB_DISPATCHER)),
        )
    }

    single<FriendshipRepository> {
        FriendshipRepositoryImpl(apiClient = get())
    }

    single<FriendCodeRepository> {
        FriendCodeRepositoryImpl(apiClient = get())
    }

    single<LevelRepository> {
        LevelRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
            clock = get(),
        )
    }

    single<ExerciseLevelRepository> {
        ExerciseLevelRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
            clock = get(),
        )
    }

    single<DailyCreditSnapshotRepository> {
        DailyCreditSnapshotRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
        )
    }

    single<JoggingSessionRepository> {
        JoggingSessionRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
            clock = get(),
        )
    }

    single<JoggingSegmentRepository> {
        JoggingSegmentRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
        )
    }

    single<JoggingPlaybackEntryRepository> {
        JoggingPlaybackEntryRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
        )
    }

    single<RoutePointRepository> {
        RoutePointRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
        )
    }

    single<ActivityStatsRepository> {
        ActivityStatsRepositoryImpl(
            database = get(),
            snapshotRepository = get(),
            dispatcher = get(named(DB_DISPATCHER)),
            clock = get(),
        )
    }

    single<RunEventRepository> {
        RunEventRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
            clock = get(),
            cloudSyncApi = getOrNull<CloudSyncApi>(),
            networkMonitor = getOrNull<NetworkMonitor>(named(NETWORK_MONITOR)),
        )
    }

    single<LiveRunSessionRepository> {
        LiveRunSessionRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
            clock = get(),
            cloudSyncApi = getOrNull<CloudSyncApi>(),
            networkMonitor = getOrNull<NetworkMonitor>(named(NETWORK_MONITOR)),
        )
    }

    single<LiveRunPresenceRepository> {
        LiveRunPresenceRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
            cloudSyncApi = getOrNull<CloudSyncApi>(),
            networkMonitor = getOrNull<NetworkMonitor>(named(NETWORK_MONITOR)),
        )
    }

    single<RunXpAwardRepository> {
        RunXpAwardRepositoryImpl(
            database = get(),
            dispatcher = get(named(DB_DISPATCHER)),
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
            levelRepository = get(),
            exerciseLevelRepository = get(),
            clock = get(),
        )
    }
    factory {
        ApplyDailyResetUseCase(
            timeCreditRepository = get(),
            sessionRepository = get(),
            snapshotRepository = get(),
            clock = get(),
        )
    }
    factory {
        GetTimeCreditUseCase(
            timeCreditRepository = get(),
            applyDailyResetUseCase = get(),
            clock = get(),
        )
    }
    factory {
        GetCreditBreakdownUseCase(
            timeCreditRepository = get(),
            sessionRepository = get(),
            applyDailyResetUseCase = get(),
            clock = get(),
        )
    }
    factory { SpendTimeCreditUseCase(timeCreditRepository = get(), clock = get()) }
    factory { GetUserSettingsUseCase(settingsRepository = get()) }
    factory { UpdateUserSettingsUseCase(settingsRepository = get()) }
    factory { GetDailyStatsUseCase(statsRepository = get()) }
    factory { GetWeeklyStatsUseCase(statsRepository = get()) }
    factory { GetMonthlyStatsUseCase(statsRepository = get()) }
    factory { GetTotalStatsUseCase(statsRepository = get()) }
    factory { CreateRunEventUseCase(repository = get(), clock = get(), idGenerator = get()) }
    factory { GetUpcomingRunEventsUseCase(repository = get()) }
    factory { RespondToRunEventUseCase(repository = get()) }
    factory { LeaveRunEventUseCase(repository = get()) }
    factory { DeleteRunEventUseCase(repository = get()) }
    factory { StartLiveRunSessionUseCase(repository = get(), clock = get(), idGenerator = get()) }
    factory { JoinLiveRunSessionUseCase(repository = get(), clock = get(), idGenerator = get()) }
    factory { LeaveLiveRunSessionUseCase(repository = get(), clock = get()) }
    factory { FinishLiveRunSessionUseCase(repository = get(), clock = get()) }
    factory { ObserveLiveRunSessionUseCase(sessionRepository = get(), presenceRepository = get()) }
    factory { ObserveFriendsActiveRunsUseCase(repository = get()) }
    factory { UpdateLiveRunPresenceUseCase(repository = get(), clock = get(), idGenerator = get()) }
    factory {
        AwardSocialRunXpUseCase(
            liveRunSessionRepository = get(),
            runXpAwardRepository = get(),
            exerciseLevelRepository = get(),
            levelRepository = get(),
            clock = get(),
            idGenerator = get(),
        )
    }
    factory { GetUserLevelUseCase(levelRepository = get()) }
    factory { AwardWorkoutXpUseCase(levelRepository = get(), exerciseLevelRepository = get()) }
    factory { GetExerciseLevelsUseCase(exerciseLevelRepository = get(), levelRepository = get()) }

    // Activity stats use-cases (unified across all workout types)
    factory { GetMonthlyActivityUseCase(activityStatsRepository = get()) }
    factory { GetActivityStreakUseCase(activityStatsRepository = get()) }

    // Jogging use-cases
    factory { StartJoggingUseCase(sessionRepository = get(), clock = get(), idGenerator = get()) }
    factory {
        RecordRoutePointUseCase(
            sessionRepository = get(),
            routePointRepository = get(),
            clock = get(),
            idGenerator = get(),
        )
    }
    factory {
        FinishJoggingUseCase(
            sessionRepository = get(),
            segmentRepository = get(),
            routePointRepository = get(),
            timeCreditRepository = get(),
            settingsRepository = get(),
            levelRepository = get(),
            exerciseLevelRepository = get(),
            awardSocialRunXpUseCase = get(),
            clock = get(),
        )
    }
    factory { SaveJoggingSegmentsUseCase(segmentRepository = get()) }
    factory { GetJoggingSegmentsUseCase(segmentRepository = get()) }
    factory { SaveJoggingPlaybackEntriesUseCase(playbackRepository = get()) }
    factory { GetJoggingPlaybackEntriesUseCase(playbackRepository = get()) }

    // Auth use-cases (Task 1B.8)
    factory { RegisterWithEmailUseCase(authRepository = get()) }
    factory { LoginWithEmailUseCase(authRepository = get()) }
    factory { LoginWithAppleUseCase(authRepository = get()) }
    factory { LoginWithGoogleUseCase(authRepository = get()) }
    factory { LogoutUseCase(authRepository = get()) }
    factory { GetCurrentUserUseCase(authRepository = get()) }
    factory { RefreshTokenUseCase(authRepository = get()) }

    // Sync use-cases (Task 1B.9)
    factory {
        SyncWorkoutsUseCase(
            sessionRepository = get(),
            supabaseClient = get<CloudSyncApi>(),
            networkMonitor = get(named(NETWORK_MONITOR)),
        )
    }
    factory {
        SyncTimeCreditUseCase(
            timeCreditRepository = get(),
            supabaseClient = get<CloudSyncApi>(),
            networkMonitor = get(named(NETWORK_MONITOR)),
        )
    }
    factory {
        SyncLevelUseCase(
            levelRepository = get(),
            supabaseClient = get<CloudSyncApi>(),
            networkMonitor = get(named(NETWORK_MONITOR)),
        )
    }
    factory {
        SyncExerciseLevelsUseCase(
            exerciseLevelRepository = get(),
            supabaseClient = get<CloudSyncApi>(),
            networkMonitor = get(named(NETWORK_MONITOR)),
        )
    }
    factory {
        SyncJoggingUseCase(
            sessionRepository = get(),
            segmentRepository = get(),
            routePointRepository = get(),
            playbackRepository = get(),
            supabaseClient = get<CloudSyncApi>(),
            networkMonitor = get(named(NETWORK_MONITOR)),
        )
    }
    factory {
        UserSettingsDashboardSyncUseCase(
            getUserSettingsUseCase = get(),
            updateUserSettingsUseCase = get(),
            cloudSyncApi = get<CloudSyncApi>(),
            networkMonitor = get(named(NETWORK_MONITOR)),
        )
    }
    factory {
        SyncFromCloudUseCase(
            sessionRepository = get(),
            timeCreditRepository = get(),
            userRepository = get(),
            joggingSessionRepository = get(),
            joggingPlaybackEntryRepository = get(),
            joggingSegmentRepository = get(),
            routePointRepository = get(),
            supabaseClient = get<CloudSyncApi>(),
            networkMonitor = get(named(NETWORK_MONITOR)),
            userSettingsDashboardSync = get(),
        )
    }
    single {
        LiveJoggingSessionManager(
            cloudSyncApi = get<CloudSyncApi>(),
            routePointRepository = get(),
            networkMonitor = get(named(NETWORK_MONITOR)),
        )
    }
    single {
        SyncManager(
            syncWorkoutsUseCase = get(),
            syncTimeCreditUseCase = get(),
            syncLevelUseCase = get(),
            syncExerciseLevelsUseCase = get(),
            syncJoggingUseCase = get(),
            syncFromCloudUseCase = get(),
            authRepository = get(),
        )
    }
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
 * Named Koin qualifier for the Supabase publishable (public) API key.
 *
 * Previously called the "anon key". Supabase renamed it to "publishable key"
 * in their new key design. The key is still sent as the `apikey` header on
 * every Supabase request and is safe to embed in client-side code.
 *
 * Bind this in your platform-specific module (or override in tests):
 * ```kotlin
 * single<String>(named(SUPABASE_PUBLISHABLE_KEY)) { BuildConfig.SUPABASE_PUBLISHABLE_KEY }
 * ```
 */
const val SUPABASE_PUBLISHABLE_KEY = "supabase_publishable_key"

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
 * Named Koin qualifier for the debug flag.
 *
 * Bind this in your platform-specific module:
 * ```kotlin
 * single<Boolean>(named(IS_DEBUG)) { BuildConfig.DEBUG }
 * ```
 * Defaults to `false` when not bound (production-safe).
 */
const val IS_DEBUG = "is_debug"

/**
 * Named Koin qualifier for the [com.sinura.domain.usecase.sync.NetworkMonitor] binding.
 *
 * Bind a platform-specific implementation in your platform module:
 * ```kotlin
 * // Android
 * single<NetworkMonitor>(named(NETWORK_MONITOR)) { AndroidNetworkMonitor(get()) }
 * // iOS
 * single<NetworkMonitor>(named(NETWORK_MONITOR)) { IosNetworkMonitor() }
 * ```
 * In tests, use [com.sinura.domain.usecase.sync.AlwaysConnectedNetworkMonitor] or
 * [com.sinura.domain.usecase.sync.AlwaysOfflineNetworkMonitor].
 */
const val NETWORK_MONITOR = "network_monitor"

/**
 * API module: binds the [io.ktor.client.HttpClient], [SupabaseClient], and
 * [KtorApiClient] as **singletons**.
 *
 * Requires the following named bindings to be provided by the platform-specific
 * module before this module is used:
 * - `String` named [SUPABASE_URL]
 * - `String` named [SUPABASE_PUBLISHABLE_KEY]
 * - `String` named [BACKEND_BASE_URL]
 * - [JwtTokenProvider] named [JWT_TOKEN_PROVIDER]
 *
 * Optionally accepts:
 * - `Boolean` named [IS_DEBUG] -- enables HTTP header logging in debug builds.
 *   Defaults to `false` when not bound.
 *
 * In development / testing, these can be provided via a test module that
 * supplies mock values.
 */
val apiModule: Module = module {
    // Shared HttpClient -- one instance for both API clients.
    // Resolves IS_DEBUG from Koin; defaults to false if not bound (production-safe).
    single {
        val isDebug = runCatching { get<Boolean>(named(IS_DEBUG)) }.getOrDefault(false)
        createHttpClient(isDebug = isDebug)
    }

    // Supabase REST API client (PostgREST) -- also bound as CloudSyncApi for sync use-cases
    single {
        val tokenProvider: JwtTokenProvider = get(named(JWT_TOKEN_PROVIDER))
        SupabaseClient(
            httpClient = get(),
            supabaseUrl = get(named(SUPABASE_URL)),
            supabasePublishableKey = get(named(SUPABASE_PUBLISHABLE_KEY)),
            tokenProvider = { tokenProvider.getToken() },
            clock = get(),
        )
    }
    single<CloudSyncApi> { get<SupabaseClient>() }

    // Supabase Auth API client (bound as AuthClient interface for testability)
    single<AuthClient> {
        SupabaseAuthClient(
            httpClient = get(),
            supabaseUrl = get(named(SUPABASE_URL)),
            supabasePublishableKey = get(named(SUPABASE_PUBLISHABLE_KEY)),
            clock = get(),
        )
    }

    // Custom Ktor backend client
    single {
        val tokenProvider: JwtTokenProvider = get(named(JWT_TOKEN_PROVIDER))
        val authRepository: AuthRepository = get()
        KtorApiClient(
            httpClient = get(),
            backendBaseUrl = get(named(BACKEND_BASE_URL)),
            tokenProvider = { tokenProvider.getToken() },
            onRefreshToken = { authRepository.refreshToken() },
        )
    }

    // Friendship / user-search API client
    single {
        val tokenProvider: JwtTokenProvider = get(named(JWT_TOKEN_PROVIDER))
        val authRepository: AuthRepository = get()
        FriendshipApiClient(
            httpClient = get(),
            backendBaseUrl = get(named(BACKEND_BASE_URL)),
            tokenProvider = { tokenProvider.getToken() },
            onRefreshToken = { authRepository.refreshToken() },
        )
    }

    // Friend code API client
    single {
        val tokenProvider: JwtTokenProvider = get(named(JWT_TOKEN_PROVIDER))
        val authRepository: AuthRepository = get()
        FriendCodeApiClient(
            httpClient = get(),
            backendBaseUrl = get(named(BACKEND_BASE_URL)),
            tokenProvider = { tokenProvider.getToken() },
            onRefreshToken = { authRepository.refreshToken() },
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
 * to provide the named string bindings ([SUPABASE_URL], [SUPABASE_PUBLISHABLE_KEY],
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

