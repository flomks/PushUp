package com.flomks.sinura.db

import app.cash.sqldelight.db.SqlDriver

/**
 * Platform-agnostic factory for creating [SqlDriver] instances.
 *
 * Each platform provides its own implementation:
 * - Android: [AndroidSqliteDriver] backed by the Android SQLite framework.
 * - iOS: [NativeSqliteDriver] backed by the co.touchlab SQLiter library.
 * - JVM/Desktop: [JdbcSqliteDriver] backed by xerial sqlite-jdbc.
 */
interface DatabaseDriverFactory {
    fun createDriver(): SqlDriver
}
