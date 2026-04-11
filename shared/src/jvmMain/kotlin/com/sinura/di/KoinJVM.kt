package com.sinura.di

import com.flomks.sinura.db.DatabaseDriverFactory
import com.flomks.sinura.db.JvmDatabaseDriverFactory
import com.sinura.data.storage.TokenStorage
import org.koin.core.context.startKoin
import org.koin.core.module.Module
import org.koin.core.qualifier.named
import org.koin.dsl.module

/**
 * JVM/Desktop-specific Koin module.
 *
 * Provides:
 * - [JvmDatabaseDriverFactory] as the platform [DatabaseDriverFactory] implementation.
 * - [TokenStorage] backed by an in-memory store (JVM/Desktop builds and unit tests).
 *
 * By default the factory uses a persistent file-based SQLite database stored in
 * `~/.pushup/pushup.db`. Pass a custom [dbPath] to override the location, or
 * pass [app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver.IN_MEMORY] for
 * an in-memory database (useful for integration tests that bypass [KoinTestHelper]).
 */
val jvmModule = module {
    single<DatabaseDriverFactory> { JvmDatabaseDriverFactory() }
    single { TokenStorage() }

    // Custom Ktor backend base URL -- hardcoded so it persists across builds
    // without requiring manual configuration or GitHub secrets.
    single<String>(named(BACKEND_BASE_URL)) { "https://api.sinura.fun" }
}

/**
 * Initialises Koin for the JVM/Desktop application.
 *
 * Call this function at the very start of `main()`, before the Compose
 * `application { }` block is entered:
 *
 * ```kotlin
 * fun main() {
 *     initKoin()
 *     application {
 *         Window(onCloseRequest = ::exitApplication) { App() }
 *     }
 * }
 * ```
 *
 * @param extraModules Additional Koin modules to load (e.g. presentation-layer
 *   ViewModel modules from the composeApp layer).
 */
fun initKoin(vararg extraModules: Module) {
    startKoin {
        modules(listOf(jvmModule) + sharedModules + extraModules.toList())
    }
}
