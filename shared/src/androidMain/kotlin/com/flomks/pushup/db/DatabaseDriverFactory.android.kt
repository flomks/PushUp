package com.flomks.pushup.db

import android.content.Context
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.android.AndroidSqliteDriver
import com.pushup.db.PushUpDatabase

/**
 * Android implementation of [DatabaseDriverFactory].
 *
 * Uses [AndroidSqliteDriver] which delegates to the platform SQLite via
 * the Android framework's `android.database.sqlite` package.
 *
 * @param context Application context used to open or create the database file.
 */
class AndroidDatabaseDriverFactory(
    private val context: Context,
) : DatabaseDriverFactory {

    override fun createDriver(): SqlDriver {
        return AndroidSqliteDriver(
            schema = PushUpDatabase.Schema,
            context = context,
            name = DB_NAME,
        )
    }

    private companion object {
        const val DB_NAME = "pushup.db"
    }
}
