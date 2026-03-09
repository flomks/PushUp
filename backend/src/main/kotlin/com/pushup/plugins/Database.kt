package com.pushup.plugins

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import io.ktor.server.application.Application
import io.ktor.server.application.log
import org.jetbrains.exposed.sql.Database
import org.jetbrains.exposed.sql.Table
import org.jetbrains.exposed.sql.kotlin.datetime.timestampWithTimeZone

// ---------------------------------------------------------------------------
// Friendship status values -- mirror the public.friendship_status PostgreSQL enum
// ---------------------------------------------------------------------------

/**
 * Kotlin representation of the `public.friendship_status` PostgreSQL enum.
 *
 * Values:
 *   PENDING  -- friend request sent, awaiting a response
 *   ACCEPTED -- both users are friends
 *   DECLINED -- receiver explicitly rejected the request
 */
enum class FriendshipStatus {
    PENDING,
    ACCEPTED,
    DECLINED,
    ;

    /** Returns the lowercase string stored in the database enum column. */
    fun toDbValue(): String = name.lowercase()

    companion object {
        /** Parses a database enum string (case-insensitive) back to [FriendshipStatus]. */
        fun fromDbValue(value: String): FriendshipStatus =
            entries.first { it.name.equals(value, ignoreCase = true) }
    }
}

// ---------------------------------------------------------------------------
// Exposed table definitions (mirror the Supabase PostgreSQL schema)
// ---------------------------------------------------------------------------

object Users : Table("users") {
    val id          = uuid("id")
    val email       = text("email")
    val username    = text("username").nullable()
    val displayName = text("display_name").nullable()
    val avatarUrl   = text("avatar_url").nullable()
    val createdAt   = timestampWithTimeZone("created_at")
    val updatedAt   = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}

/**
 * Mirrors the public.time_credits table in Supabase.
 * One row per user -- tracks accumulated earned and spent screen-time credits.
 */
object TimeCredits : Table("time_credits") {
    val id                 = uuid("id")
    val userId             = uuid("user_id").references(Users.id)
    val totalEarnedSeconds = long("total_earned_seconds")
    val totalSpentSeconds  = long("total_spent_seconds")
    val updatedAt          = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}

/**
 * Mirrors the public.friendships table in Supabase.
 *
 * One row per directed friend request.  The pair (requester_id, receiver_id)
 * is unique -- only one request can exist between any two users at a time.
 *
 * Status lifecycle:
 *   pending  -> accepted  (receiver accepts)
 *   pending  -> declined  (receiver declines)
 *   any      -> (deleted) (either party cancels / unfriends)
 *
 * The [status] column is stored as a PostgreSQL enum (`friendship_status`).
 * Exposed reads it as a plain [String]; use [FriendshipStatus.fromDbValue] to
 * convert to the Kotlin enum and [FriendshipStatus.toDbValue] to write it back.
 */
object Friendships : Table("friendships") {
    val id          = uuid("id")
    val requesterId = uuid("requester_id").references(Users.id)
    val receiverId  = uuid("receiver_id").references(Users.id)

    /**
     * Stored as the PostgreSQL `friendship_status` enum.
     * Exposed does not have built-in support for custom PG enums, so the
     * column is mapped to [String].  Use [FriendshipStatus] for type-safe
     * access in application code.
     */
    val status      = varchar("status", 16)

    val createdAt   = timestampWithTimeZone("created_at")
    val updatedAt   = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}


/**
 * Kotlin representation of the `public.notification_type` PostgreSQL enum.
 *
 * Values:
 *   FRIEND_REQUEST  -- a user sent a friend request to the recipient
 *   FRIEND_ACCEPTED -- the recipient accepted a friend request
 */
enum class NotificationType {
    FRIEND_REQUEST,
    FRIEND_ACCEPTED,
    ;

    /** Returns the snake_case string stored in the database enum column. */
    fun toDbValue(): String = name.lowercase()

    companion object {
        /** Parses a database enum string (case-insensitive) back to [NotificationType]. */
        fun fromDbValue(value: String): NotificationType =
            entries.first { it.name.equals(value, ignoreCase = true) }
    }
}

/**
 * Mirrors the public.notifications table in Supabase.
 *
 * One row per in-app notification delivered to a user.
 * Notifications are soft-deleted by marking them as read (isRead = true).
 *
 * The [type] column is stored as the PostgreSQL `notification_type` enum.
 * Exposed reads it as a plain [String]; use [NotificationType.fromDbValue] to
 * convert to the Kotlin enum and [NotificationType.toDbValue] to write it back.
 */
object Notifications : Table("notifications") {
    val id        = uuid("id")
    val userId    = uuid("user_id").references(Users.id)
    val type      = varchar("type", 32)
    val actorId   = uuid("actor_id").references(Users.id).nullable()
    val payload   = text("payload")
    val isRead    = bool("is_read")
    val createdAt = timestampWithTimeZone("created_at")
    val updatedAt = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}


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
 *
 * @return true if the database was successfully initialised, false if skipped
 *         (only possible in non-production mode).
 */
fun Application.configureDatabase(): Boolean {
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
        return false
    }

    log.info("Initialising database connection pool ...")

    val hikariConfig = HikariConfig().apply {
        jdbcUrl              = databaseUrl
        driverClassName      = "org.postgresql.Driver"
        maximumPoolSize      = 10
        minimumIdle          = 2
        idleTimeout          = 300_000    // 5 minutes
        connectionTimeout    = 5_000      // 5 seconds (fail fast instead of blocking 30s)
        maxLifetime          = 1_800_000  // 30 minutes
        isAutoCommit         = false
        transactionIsolation = "TRANSACTION_READ_COMMITTED"
        // Validate connections before handing them to the application.
        // Prevents stale/broken connections from causing query failures.
        connectionTestQuery  = "SELECT 1"
        // Detect connection leaks in development (logs a warning after 30s).
        leakDetectionThreshold = if (isDev) 30_000 else 0
        validate()
    }

    val dataSource = HikariDataSource(hikariConfig)
    Database.connect(dataSource)

    log.info("Database connection pool ready (pool size: ${hikariConfig.maximumPoolSize})")
    return true
}
