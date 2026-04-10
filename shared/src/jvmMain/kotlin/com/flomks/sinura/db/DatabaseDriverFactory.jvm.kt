package com.flomks.sinura.db

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.sinura.db.SinuraDatabase
import java.io.File
import java.util.Properties

/**
 * JVM/Desktop implementation of [DatabaseDriverFactory].
 *
 * Uses [JdbcSqliteDriver] backed by xerial sqlite-jdbc.
 * The database file is stored in the user's application data directory
 * (`~/.pushup/pushup.db`) by default.
 *
 * Schema creation and migration are handled automatically by the
 * [JdbcSqliteDriver] factory overload that accepts a [schema] parameter --
 * the same pattern used by [app.cash.sqldelight.driver.android.AndroidSqliteDriver]
 * and [app.cash.sqldelight.driver.native.NativeSqliteDriver] on other targets.
 * This ensures `CREATE TABLE` is only called on a brand-new database and
 * `migrate()` is called when an existing database has an older schema version.
 *
 * Foreign key enforcement is enabled via the `foreign_keys` PRAGMA so that
 * `ON DELETE CASCADE` constraints on [SinuraDatabase] tables are respected.
 *
 * @param dbPath Optional explicit path to the database file.
 *               Pass `null` to use the default location (`~/.pushup/pushup.db`).
 *               Pass [JdbcSqliteDriver.IN_MEMORY] for an in-memory database
 *               (useful for integration tests that bypass KoinTestHelper).
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

        // The JdbcSqliteDriver(url, properties, schema) factory overload handles
        // schema versioning automatically: it calls schema.create() for new databases
        // and schema.migrate() for existing ones -- no manual PRAGMA wrangling needed.
        return JdbcSqliteDriver(
            url = url,
            properties = Properties().apply { put("foreign_keys", "true") },
            schema = SinuraDatabase.Schema,
        )
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
