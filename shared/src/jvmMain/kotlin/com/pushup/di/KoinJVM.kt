package com.pushup.di

import com.flomks.pushup.db.DatabaseDriverFactory
import com.flomks.pushup.db.JvmDatabaseDriverFactory
import org.koin.core.context.startKoin
import org.koin.dsl.module

/**
 * JVM/Desktop-specific Koin module.
 *
 * Provides the [JvmDatabaseDriverFactory] as the platform [DatabaseDriverFactory]
 * implementation. This binding is required by [databaseModule] in [AppModule.kt].
 *
 * By default the factory uses a persistent file-based SQLite database stored in
 * `~/.pushup/pushup.db`. Pass a custom [dbPath] to override the location, or
 * pass [app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver.IN_MEMORY] for
 * an in-memory database (useful for integration tests that bypass [KoinTestHelper]).
 */
val jvmModule = module {
    single<DatabaseDriverFactory> { JvmDatabaseDriverFactory() }
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
 */
fun initKoin() {
    startKoin {
        modules(jvmModule + sharedModules)
    }
}
