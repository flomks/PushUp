package com.pushup.plugins

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import io.ktor.server.application.Application
import io.ktor.server.application.log
import org.jetbrains.exposed.sql.Database
import org.jetbrains.exposed.sql.Table
import org.jetbrains.exposed.sql.kotlin.datetime.timestampWithTimeZone

// ---------------------------------------------------------------------------
// Exposed table definitions (mirror the Supabase PostgreSQL schema)
// ---------------------------------------------------------------------------

object Users : Table("users") {
    val id          = uuid("id")
    val email       = text("email")
    val displayName = text("display_name").nullable()
    val avatarUrl   = text("avatar_url").nullable()
    val createdAt   = timestampWithTimeZone("created_at")
    val updatedAt   = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}

object WorkoutSessions : Table("workout_sessions") {
    val id                = uuid("id")
    val userId            = uuid("user_id").references(Users.id)
    val startedAt         = timestampWithTimeZone("started_at")
    val endedAt           = timestampWithTimeZone("ended_at").nullable()
    val pushUpCount       = integer("push_up_count")
    val earnedTimeCredits = integer("earned_time_credits")
    val quality           = float("quality")
    val createdAt         = timestampWithTimeZone("created_at")
    val updatedAt         = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}

object PushUpRecords : Table("push_up_records") {
    val id         = uuid("id")
    val sessionId  = uuid("session_id").references(WorkoutSessions.id)
    val timestamp  = timestampWithTimeZone("timestamp")
    val durationMs = integer("duration_ms").nullable()
    val depthScore = float("depth_score").nullable()
    val formScore  = float("form_score").nullable()
    val createdAt  = timestampWithTimeZone("created_at")

    override val primaryKey = PrimaryKey(id)
}

object TimeCredits : Table("time_credits") {
    val id                 = uuid("id")
    val userId             = uuid("user_id").references(Users.id)
    val totalEarnedSeconds = long("total_earned_seconds")
    val totalSpentSeconds  = long("total_spent_seconds")
    val updatedAt          = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}

object UserSettings : Table("user_settings") {
    val id                       = uuid("id")
    val userId                   = uuid("user_id").references(Users.id)
    val pushUpsPerMinuteCredit   = integer("push_ups_per_minute_credit")
    val qualityMultiplierEnabled = bool("quality_multiplier_enabled")
    val dailyCreditCapSeconds    = long("daily_credit_cap_seconds").nullable()
    val createdAt                = timestampWithTimeZone("created_at")
    val updatedAt                = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}

// ---------------------------------------------------------------------------
// Plugin installer
// ---------------------------------------------------------------------------

/**
 * Configures a HikariCP connection pool pointing at the Supabase PostgreSQL
 * database and connects Exposed to it.
 *
 * Required environment variable:
 *   DATABASE_URL  -- full JDBC connection string, e.g.
 *                    jdbc:postgresql://db.<ref>.supabase.co:5432/postgres
 *                    ?user=postgres&password=<pw>&sslmode=require
 *
 * In non-production mode (KTOR_ENV != "production") the server will log a
 * warning and skip database initialisation if DATABASE_URL is not set.
 */
fun Application.configureDatabase() {
    val databaseUrl = System.getenv("DATABASE_URL")
    val isDev = System.getenv("KTOR_ENV") != "production"

    if (databaseUrl.isNullOrBlank()) {
        if (!isDev) {
            throw IllegalStateException(
                "DATABASE_URL must be set in production. " +
                    "Set KTOR_ENV to a value other than 'production' to disable this check."
            )
        }
        log.warn("DATABASE_URL not set -- database connection is DISABLED (non-production mode)")
        return
    }

    log.info("Initialising database connection pool ...")

    val hikariConfig = HikariConfig().apply {
        jdbcUrl              = databaseUrl
        driverClassName      = "org.postgresql.Driver"
        maximumPoolSize      = 10
        minimumIdle          = 2
        idleTimeout          = 600_000    // 10 minutes
        connectionTimeout    = 30_000     // 30 seconds
        maxLifetime          = 1_800_000  // 30 minutes
        isAutoCommit         = false
        // READ_COMMITTED matches PostgreSQL's default isolation level and is
        // appropriate for the read-heavy workloads in this service.
        transactionIsolation = "TRANSACTION_READ_COMMITTED"
        validate()
    }

    val dataSource = HikariDataSource(hikariConfig)
    Database.connect(dataSource)

    log.info("Database connection pool ready (pool size: ${hikariConfig.maximumPoolSize})")
}
