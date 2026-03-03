package com.pushup.di

import com.flomks.pushup.db.DatabaseDriverFactory
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
import com.pushup.domain.usecase.FinishWorkoutUseCase
import com.pushup.domain.usecase.GetDailyStatsUseCase
import com.pushup.domain.usecase.GetMonthlyStatsUseCase
import com.pushup.domain.usecase.GetOrCreateLocalUserUseCase
import com.pushup.domain.usecase.GetTimeCreditUseCase
import com.pushup.domain.usecase.GetTotalStatsUseCase
import com.pushup.domain.usecase.GetUserSettingsUseCase
import com.pushup.domain.usecase.GetWeeklyStatsUseCase
import com.pushup.domain.usecase.RecordPushUpUseCase
import com.pushup.domain.usecase.SpendTimeCreditUseCase
import com.pushup.domain.usecase.StartWorkoutUseCase
import com.pushup.domain.usecase.UpdateUserSettingsUseCase
import kotlinx.coroutines.Dispatchers
import org.koin.core.module.Module
import org.koin.core.module.dsl.factoryOf
import org.koin.core.module.dsl.singleOf
import org.koin.dsl.bind
import org.koin.dsl.module

/**
 * Core Koin DI module for the shared KMP module.
 *
 * Wiring strategy:
 * - [PushUpDatabase] and all [*Repository] implementations are **singletons** --
 *   they hold database connections and should be shared across the app lifetime.
 * - All use-cases are **factories** -- a fresh instance is created per injection
 *   site, keeping them stateless and easy to test in isolation.
 *
 * Platform-specific modules (Android / iOS) must provide a [DatabaseDriverFactory]
 * binding before this module is loaded. The [databaseModule] declared here
 * depends on that platform binding to construct the [PushUpDatabase].
 */

/**
 * Database module: constructs the [PushUpDatabase] singleton from the
 * platform-provided [DatabaseDriverFactory].
 *
 * The [DatabaseDriverFactory] must be bound by the platform-specific module
 * (see [androidModule] / [iosModule]) before this module is used.
 */
val databaseModule: Module = module {
    single<PushUpDatabase> {
        val factory = get<DatabaseDriverFactory>()
        PushUpDatabase(factory.createDriver())
    }
}

/**
 * Repository module: binds all repository implementations as singletons.
 *
 * Each implementation is bound to its corresponding interface so that
 * use-cases and other consumers depend only on the abstraction.
 *
 * [Dispatchers.IO] is injected as the coroutine dispatcher for all
 * database-backed repositories to keep DB work off the main thread.
 */
val repositoryModule: Module = module {
    single<UserRepository> {
        UserRepositoryImpl(
            database = get(),
            dispatcher = Dispatchers.Default,
        )
    }

    single<WorkoutSessionRepository> {
        WorkoutSessionRepositoryImpl(
            database = get(),
            dispatcher = Dispatchers.Default,
        )
    }

    single<PushUpRecordRepository> {
        PushUpRecordRepositoryImpl(
            database = get(),
            dispatcher = Dispatchers.Default,
        )
    }

    single<TimeCreditRepository> {
        TimeCreditRepositoryImpl(
            database = get(),
            dispatcher = Dispatchers.Default,
        )
    }

    single<UserSettingsRepository> {
        UserSettingsRepositoryImpl(
            database = get(),
            dispatcher = Dispatchers.Default,
        )
    }

    single<StatsRepository> {
        StatsRepositoryImpl(
            database = get(),
            timeCreditRepository = get(),
            dispatcher = Dispatchers.Default,
        )
    }
}

/**
 * Use-case module: binds all use-cases as **factories**.
 *
 * A new instance is created on every injection, which keeps use-cases
 * stateless and makes them trivial to mock in unit tests.
 */
val useCaseModule: Module = module {
    factory { GetOrCreateLocalUserUseCase(userRepository = get()) }
    factory { StartWorkoutUseCase(sessionRepository = get()) }
    factory {
        RecordPushUpUseCase(
            sessionRepository = get(),
            recordRepository = get(),
        )
    }
    factory {
        FinishWorkoutUseCase(
            sessionRepository = get(),
            recordRepository = get(),
            timeCreditRepository = get(),
            settingsRepository = get(),
        )
    }
    factory { GetTimeCreditUseCase(timeCreditRepository = get()) }
    factory { SpendTimeCreditUseCase(timeCreditRepository = get()) }
    factory { GetUserSettingsUseCase(settingsRepository = get()) }
    factory { UpdateUserSettingsUseCase(settingsRepository = get()) }
    factory { GetDailyStatsUseCase(statsRepository = get()) }
    factory { GetWeeklyStatsUseCase(statsRepository = get()) }
    factory { GetMonthlyStatsUseCase(statsRepository = get()) }
    factory { GetTotalStatsUseCase(statsRepository = get()) }
}

/**
 * Aggregated list of all shared modules.
 *
 * Platform entry points ([initKoin] on Android / iOS) should pass this list
 * together with their platform-specific module to [startKoin].
 */
val sharedModules: List<Module> = listOf(
    databaseModule,
    repositoryModule,
    useCaseModule,
)
