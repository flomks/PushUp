package com.flomks.pushup.db

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.pushup.db.PushUpDatabase
import java.io.File

/**
 * JVM/Desktop implementation of [DatabaseDriverFactory].
 *
 * Uses [JdbcSqliteDriver] backed by xerial sqlite-jdbc.
 * The database file is stored in the user's application data directory.
 *
 * @param dbPath Optional explicit path to the database file.
 *               Pass `null` (or [JdbcSqliteDriver.IN_MEMORY]) for an
 *               in-memory database, useful for testing.
 */
class JvmDatabaseDriverFactory(
    private val dbPath: String? = null,
) : DatabaseDriverFactory {

    override fun createDriver(): SqlDriver {
        val url = when {
            dbPath == null -> defaultDbUrl()
            dbPath == JdbcSqliteDriver.IN_MEMORY -> JdbcSqliteDriver.IN_MEMORY
            else -> "jdbc:sqlite:$dbPath"
        }

        val driver = JdbcSqliteDriver(url)
        PushUpDatabase.Schema.create(driver)
        return driver
    }

    private fun defaultDbUrl(): String {
        val appDir = File(System.getProperty("user.home"), ".pushup")
        appDir.mkdirs()
        return "jdbc:sqlite:${File(appDir, DB_NAME).absolutePath}"
    }

    private companion object {
        const val DB_NAME = "pushup.db"
    }
}
