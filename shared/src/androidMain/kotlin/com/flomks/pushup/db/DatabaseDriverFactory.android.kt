package com.flomks.pushup.db

import android.content.Context
import androidx.sqlite.db.SupportSQLiteDatabase
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.android.AndroidSqliteDriver
import com.pushup.db.PushUpDatabase

/**
 * Android implementation of [DatabaseDriverFactory].
 *
 * Uses [AndroidSqliteDriver] which delegates to the platform SQLite via
 * the Android framework's `android.database.sqlite` package.
 *
 * Foreign key enforcement is enabled via `PRAGMA foreign_keys = ON` so that
 * `ON DELETE CASCADE` constraints in the schema fire correctly when a User row
 * is deleted. Without this pragma, SQLite silently ignores all FK constraints
 * and orphaned child rows (WorkoutSession, TimeCredit, UserLevel, UserSettings)
 * accumulate in the database across logout/login cycles.
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
            callback = object : AndroidSqliteDriver.Callback(PushUpDatabase.Schema) {
                override fun onOpen(db: SupportSQLiteDatabase) {
                    db.execSQL("PRAGMA foreign_keys = ON")
                }
            },
        )
    }

    private companion object {
        const val DB_NAME = "pushup.db"
    }
}
