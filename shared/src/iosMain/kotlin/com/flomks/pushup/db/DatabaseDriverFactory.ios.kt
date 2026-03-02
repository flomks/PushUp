package com.flomks.pushup.db

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.native.NativeSqliteDriver
import com.pushup.db.PushUpDatabase

/**
 * iOS implementation of [DatabaseDriverFactory].
 *
 * Uses [NativeSqliteDriver] which delegates to SQLite via the
 * co.touchlab SQLiter library for Kotlin/Native.
 */
class IosDatabaseDriverFactory : DatabaseDriverFactory {

    override fun createDriver(): SqlDriver {
        return NativeSqliteDriver(
            schema = PushUpDatabase.Schema,
            name = DB_NAME,
        )
    }

    private companion object {
        const val DB_NAME = "pushup.db"
    }
}
