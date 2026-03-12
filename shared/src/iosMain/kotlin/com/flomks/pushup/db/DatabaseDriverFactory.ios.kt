package com.flomks.pushup.db

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.native.NativeSqliteDriver
import co.touchlab.sqliter.DatabaseConfiguration
import com.pushup.db.PushUpDatabase

/**
 * iOS implementation of [DatabaseDriverFactory].
 *
 * Uses [NativeSqliteDriver] which delegates to SQLite via the
 * co.touchlab SQLiter library for Kotlin/Native.
 *
 * Foreign key enforcement is enabled via `PRAGMA foreign_keys = ON` so that
 * `ON DELETE CASCADE` constraints in the schema fire correctly when a User row
 * is deleted. Without this pragma, SQLite silently ignores all FK constraints
 * and orphaned child rows (WorkoutSession, TimeCredit, UserLevel, UserSettings)
 * accumulate in the database across logout/login cycles.
 */
class IosDatabaseDriverFactory : DatabaseDriverFactory {

    override fun createDriver(): SqlDriver {
        return NativeSqliteDriver(
            schema = PushUpDatabase.Schema,
            name = DB_NAME,
            onConfiguration = { config ->
                config.copy(
                    extendedConfig = DatabaseConfiguration.Extended(
                        foreignKeyConstraints = true,
                    ),
                )
            },
        )
    }

    private companion object {
        const val DB_NAME = "pushup.db"
    }
}
