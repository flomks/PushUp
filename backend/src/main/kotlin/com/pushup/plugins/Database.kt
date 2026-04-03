package com.pushup.plugins

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import io.ktor.server.application.Application
import io.ktor.server.application.log
import org.jetbrains.exposed.sql.Column
import org.jetbrains.exposed.sql.CustomFunction
import org.jetbrains.exposed.sql.Database
import org.jetbrains.exposed.sql.Index
import org.jetbrains.exposed.sql.SchemaUtils
import org.jetbrains.exposed.sql.Table
import org.jetbrains.exposed.sql.kotlin.datetime.timestampWithTimeZone
import org.jetbrains.exposed.sql.javatime.JavaInstantColumnType
import org.jetbrains.exposed.sql.statements.api.PreparedStatementApi
import org.jetbrains.exposed.sql.stringParam
import org.jetbrains.exposed.sql.transactions.transaction
import org.jetbrains.exposed.sql.vendors.currentDialect
import org.jetbrains.exposed.sql.IColumnType
import org.postgresql.util.PGobject

// ---------------------------------------------------------------------------
// PostgreSQL custom enum column helper
// ---------------------------------------------------------------------------

/**
 * Exposed [IColumnType] for PostgreSQL `jsonb` columns.
 *
 * Stores and retrieves JSON as a plain [String] in Kotlin, but wraps it in a
 * [PGobject] with type `"jsonb"` when sending to PostgreSQL so the driver
 * uses the correct wire type instead of `character varying`.
 */
class JsonbColumnType : IColumnType<String> {
    override var nullable: Boolean = false

    override fun sqlType(): String = "jsonb"

    override fun valueFromDB(value: Any): String = when (value) {
        is PGobject -> value.value ?: "{}"
        is String   -> value
        else        -> value.toString()
    }

    override fun notNullValueToDB(value: String): Any =
        PGobject().apply {
            type = "jsonb"
            this.value = value
        }

    override fun setParameter(stmt: PreparedStatementApi, index: Int, value: Any?) {
        val pgObj = if (value == null) {
            PGobject().apply { type = "jsonb"; this.value = null }
        } else {
            PGobject().apply { type = "jsonb"; this.value = value.toString() }
        }
        stmt[index] = pgObj
    }
}

/**
 * Creates an Exposed column that maps to a PostgreSQL custom enum type.
 *
 * PostgreSQL enforces strict type matching: comparing a custom enum column
 * with a plain `varchar` parameter fails with
 * "operator does not exist: <enum_type> = character varying".
 *
 * This helper wraps the value in a [PGobject] with the correct type name so
 * the JDBC driver sends it as the proper PostgreSQL enum type, satisfying the
 * type-matching requirement without requiring explicit SQL casts.
 *
 * @param columnName  The database column name.
 * @param pgTypeName  The PostgreSQL enum type name (e.g. "friendship_status").
 * @param T           The Kotlin enum class. Must implement [PgEnumValue].
 */
inline fun <reified T> Table.pgEnum(
    columnName: String,
    pgTypeName: String,
): Column<T> where T : Enum<T>, T : PgEnumValue =
    customEnumeration(
        name        = columnName,
        sql         = pgTypeName,
        fromDb      = { value ->
            val str = when (value) {
                is PGobject -> value.value ?: error("NULL enum value for $pgTypeName")
                else        -> value.toString()
            }
            enumValues<T>().first { it.pgValue.equals(str, ignoreCase = true) }
        },
        toDb        = { enumVal ->
            PGobject().apply {
                type  = pgTypeName
                this.value = enumVal.pgValue
            }
        },
    )

/**
 * Interface for Kotlin enums that map to PostgreSQL enum values.
 * Implement [pgValue] to return the exact string stored in the database.
 */
interface PgEnumValue {
    val pgValue: String
}

/**
 * Creates an Exposed column that maps to a PostgreSQL `jsonb` column.
 *
 * Exposed's built-in [text] column sends values as `character varying`, which
 * PostgreSQL rejects when the target column type is `jsonb`:
 * "column is of type jsonb but expression is of type character varying".
 *
 * This helper wraps the string value in a [PGobject] with type `"jsonb"` so
 * the JDBC driver sends it with the correct PostgreSQL type, satisfying the
 * strict type-matching requirement without requiring explicit SQL casts.
 *
 * @param columnName The database column name.
 */
fun Table.jsonb(columnName: String): Column<String> =
    registerColumn(columnName, JsonbColumnType())

// ---------------------------------------------------------------------------
// Friend code privacy values -- mirror the public.friend_code_privacy PostgreSQL enum
// ---------------------------------------------------------------------------

/**
 * Kotlin representation of the `public.friend_code_privacy` PostgreSQL enum.
 *
 * Values:
 *   AUTO_ACCEPT      -- anyone who uses the code is added as a friend immediately
 *   REQUIRE_APPROVAL -- using the code creates a pending friend request
 *   INACTIVE         -- the code is disabled; attempts to use it are rejected
 */
enum class FriendCodePrivacy(override val pgValue: String) : PgEnumValue {
    AUTO_ACCEPT("auto_accept"),
    REQUIRE_APPROVAL("require_approval"),
    INACTIVE("inactive"),
    ;

    fun toDbValue(): String = pgValue

    companion object {
        fun fromDbValue(value: String): FriendCodePrivacy =
            entries.first { it.pgValue.equals(value, ignoreCase = true) }
    }
}

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
enum class FriendshipStatus(override val pgValue: String) : PgEnumValue {
    PENDING("pending"),
    ACCEPTED("accepted"),
    DECLINED("declined"),
    ;

    /** Returns the lowercase string stored in the database enum column. */
    fun toDbValue(): String = pgValue

    companion object {
        /** Parses a database enum string (case-insensitive) back to [FriendshipStatus]. */
        fun fromDbValue(value: String): FriendshipStatus =
            entries.first { it.pgValue.equals(value, ignoreCase = true) }
    }
}

// ---------------------------------------------------------------------------
// Exposed table definitions (mirror the Supabase PostgreSQL schema)
// ---------------------------------------------------------------------------

object Users : Table("users") {
    val id                = uuid("id")
    val email             = text("email")
    val username          = text("username").nullable()
    val displayName       = text("display_name").nullable()
    val avatarUrl         = text("avatar_url").nullable()         // OAuth provider avatar
    val customAvatarUrl   = text("custom_avatar_url").nullable()  // user-uploaded avatar (priority)
    val avatarVisibility  = text("avatar_visibility")             // 'everyone' | 'friends_only' | 'nobody'
    val createdAt         = timestampWithTimeZone("created_at")
    val updatedAt         = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)

    /**
     * Returns the effective avatar URL for a result row:
     * custom_avatar_url takes priority over avatar_url (OAuth).
     */
    fun resolvedAvatarUrl(row: org.jetbrains.exposed.sql.ResultRow): String? =
        row[customAvatarUrl] ?: row[avatarUrl]
}

/**
 * Mirrors the public.user_settings table in Supabase.
 * One row per user -- per-user configuration for the credit system.
 */
object UserSettings : Table("user_settings") {
    val id                       = uuid("id")
    val userId                   = uuid("user_id").references(Users.id)
    val pushUpsPerMinuteCredit   = integer("push_ups_per_minute_credit")
    val qualityMultiplierEnabled = bool("quality_multiplier_enabled")
    val dailyCreditCapSeconds    = long("daily_credit_cap_seconds").nullable()
    val searchableByEmail        = bool("searchable_by_email")
    val dashboardWidgetOrderJson = text("dashboard_widget_order_json").nullable()
    val createdAt                = timestampWithTimeZone("created_at")
    val updatedAt                = timestampWithTimeZone("updated_at")

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
    val dailyEarnedSeconds = long("daily_earned_seconds").default(0L)
    val dailySpentSeconds  = long("daily_spent_seconds").default(0L)
    val lastResetAt        = timestampWithTimeZone("last_reset_at").nullable()
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
     * Mapped via [pgEnum] so Exposed sends the value as a typed PGobject
     * rather than a plain varchar -- this satisfies PostgreSQL's strict
     * operator type-matching (`friendship_status = friendship_status`).
     */
    val status = pgEnum<FriendshipStatus>("status", "friendship_status")

    val createdAt   = timestampWithTimeZone("created_at")
    val updatedAt   = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}


/**
 * Stores APNs device tokens for push notification delivery.
 *
 * One row per (user, token) pair. A user may have multiple devices.
 * Tokens are upserted on each app launch so stale tokens are replaced
 * automatically when Apple rotates them.
 *
 * The [platform] column is reserved for future Android (FCM) support.
 */
object DeviceTokens : Table("device_tokens") {
    val id        = uuid("id")
    val userId    = uuid("user_id").references(Users.id)
    val token     = text("token")
    val platform  = text("platform")   // "apns" | "fcm"
    val createdAt = timestampWithTimeZone("created_at")
    val updatedAt = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)

    /** Mirrors `idx_device_tokens_user_id` created by migration 003. */
    val idxUserId = Index(
        columns    = listOf(userId),
        unique     = false,
        customName = "idx_device_tokens_user_id",
    )
}

/**
 * Mirrors the public.user_levels table in Supabase.
 * One row per user -- tracks accumulated XP.
 * The current level is derived from [totalXp] on the client via LevelCalculator.
 */
object UserLevels : Table("user_levels") {
    val id        = uuid("id")
    val userId    = uuid("user_id").references(Users.id)
    val totalXp   = long("total_xp")
    val updatedAt = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)

    /**
     * Mirrors `idx_user_levels_user_id` (non-unique) created by migration 007.
     * The `user_levels_user_id_key` unique constraint is enforced by the
     * `UNIQUE` keyword on the column definition in the migration DDL; Exposed
     * sees it as a separate unique index and maps it via [idxUserIdUnique].
     */
    val idxUserId = Index(
        columns    = listOf(userId),
        unique     = false,
        customName = "idx_user_levels_user_id",
    )
    val idxUserIdUnique = Index(
        columns    = listOf(userId),
        unique     = true,
        customName = "user_levels_user_id_key",
    )
}

/**
 * Mirrors the public.notifications table in Supabase.
 * One row per in-app notification delivered to a user.
 */
object Notifications : Table("notifications") {
    val id        = uuid("id")
    val userId    = uuid("user_id").references(Users.id)
    val type      = text("type")           // notification_type enum value as text
    val actorId   = uuid("actor_id").nullable()
    val payload   = jsonb("payload")
    val isRead    = bool("is_read")
    val createdAt = timestampWithTimeZone("created_at")
    val updatedAt = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)

    /** Mirrors `idx_notifications_user_id` created by migration 006. */
    val idxUserId = Index(
        columns    = listOf(userId),
        unique     = false,
        customName = "idx_notifications_user_id",
    )

    /**
     * Mirrors `idx_notifications_user_is_read` created by migration 006.
     * Used to efficiently query unread notifications for a user.
     */
    val idxUserIsRead = Index(
        columns    = listOf(userId, isRead),
        unique     = false,
        customName = "idx_notifications_user_is_read",
    )

    /**
     * Mirrors `idx_notifications_user_created_at` created by migration 006.
     * Used for paginated notification feeds ordered by creation time.
     */
    val idxUserCreatedAt = Index(
        columns    = listOf(userId, createdAt),
        unique     = false,
        customName = "idx_notifications_user_created_at",
    )
}

/**
 * Mirrors the public.friend_codes table in Supabase.
 * One row per user -- each user has exactly one friend code at a time.
 *
 * The code can be reset (new value generated) or deactivated via the
 * [privacy] column.
 */
object FriendCodes : Table("friend_codes") {
    val id        = uuid("id")
    val userId    = uuid("user_id").references(Users.id)
    val code      = text("code")
    val privacy   = pgEnum<FriendCodePrivacy>("privacy", "friend_code_privacy")
    val createdAt = timestampWithTimeZone("created_at")
    val updatedAt = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)

    val idxCode = Index(
        columns    = listOf(code),
        unique     = true,
        customName = "idx_friend_codes_code",
    )
    val idxUserId = Index(
        columns    = listOf(userId),
        unique     = true,
        customName = "idx_friend_codes_user_id",
    )
}

// ---------------------------------------------------------------------------
// Social running tables -- mirror the public.run_events / live_run_sessions
// foundation created by migration 019.
// ---------------------------------------------------------------------------

/**
 * Mirrors the public.run_events table in Supabase.
 * Stores planned social running events.
 */
object RunEvents : Table("run_events") {
    val id               = uuid("id")
    val createdBy        = uuid("created_by").references(Users.id)
    val title            = text("title")
    val description      = text("description").nullable()
    val mode             = text("mode")
    val visibility       = text("visibility")
    val plannedStartAt   = timestampWithTimeZone("planned_start_at")
    val plannedEndAt     = timestampWithTimeZone("planned_end_at").nullable()
    val checkInOpensAt   = timestampWithTimeZone("check_in_opens_at")
    val status           = text("status")
    val locationName     = text("location_name").nullable()
    val createdAt        = timestampWithTimeZone("created_at")
    val updatedAt        = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}

/**
 * Mirrors the public.live_run_sessions table in Supabase.
 * Tracks active or cooling-down social run sessions.
 */
object LiveRunSessions : Table("live_run_sessions") {
    val id                = uuid("id")
    val sourceType        = text("source_type")
    val linkedEventId     = uuid("linked_event_id").nullable().references(RunEvents.id)
    val leaderUserId      = uuid("leader_user_id").references(Users.id)
    val visibility        = text("visibility")
    val mode              = text("mode")
    val state             = text("state")
    val startedAt         = timestampWithTimeZone("started_at")
    val cooldownStartedAt = timestampWithTimeZone("cooldown_started_at").nullable()
    val endedAt           = timestampWithTimeZone("ended_at").nullable()
    val lastActivityAt    = timestampWithTimeZone("last_activity_at")
    val maxEndsAt         = timestampWithTimeZone("max_ends_at")
    val createdAt         = timestampWithTimeZone("created_at")
    val updatedAt         = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}

/**
 * Mirrors the public.run_event_participants table in Supabase.
 */
object RunEventParticipants : Table("run_event_participants") {
    val id          = uuid("id")
    val eventId     = uuid("event_id").references(RunEvents.id)
    val userId      = uuid("user_id").references(Users.id)
    val role        = text("role")
    val status      = text("status")
    val invitedBy   = uuid("invited_by").nullable().references(Users.id)
    val invitedAt   = timestampWithTimeZone("invited_at").nullable()
    val respondedAt = timestampWithTimeZone("responded_at").nullable()
    val checkedInAt = timestampWithTimeZone("checked_in_at").nullable()
    val createdAt   = timestampWithTimeZone("created_at")
    val updatedAt   = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}

/**
 * Mirrors the public.live_run_participants table in Supabase.
 */
object LiveRunParticipants : Table("live_run_participants") {
    val id             = uuid("id")
    val sessionId      = uuid("session_id").references(LiveRunSessions.id)
    val userId         = uuid("user_id").references(Users.id)
    val status         = text("status")
    val joinedAt       = timestampWithTimeZone("joined_at")
    val becameActiveAt = timestampWithTimeZone("became_active_at").nullable()
    val finishedAt     = timestampWithTimeZone("finished_at").nullable()
    val leftAt         = timestampWithTimeZone("left_at").nullable()
    val isLeader       = bool("is_leader")
    val createdAt      = timestampWithTimeZone("created_at")
    val updatedAt      = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}

/**
 * Mirrors the public.live_run_presence table in Supabase.
 */
object LiveRunPresence : Table("live_run_presence") {
    val id                       = uuid("id")
    val sessionId                = uuid("session_id").references(LiveRunSessions.id)
    val userId                   = uuid("user_id").references(Users.id)
    val presenceState            = text("presence_state")
    val lastSeenAt               = timestampWithTimeZone("last_seen_at")
    val currentDistanceMeters    = float("current_distance_meters")
    val currentDurationSeconds   = integer("current_duration_seconds")
    val currentPaceSecondsPerKm  = integer("current_pace_seconds_per_km").nullable()
    val currentLatitude          = double("current_latitude").nullable()
    val currentLongitude         = double("current_longitude").nullable()
    val updatedAt                = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}

/**
 * Mirrors the public.run_xp_awards table in Supabase.
 */
object RunXpAwards : Table("run_xp_awards") {
    val id               = uuid("id")
    val userId           = uuid("user_id").references(Users.id)
    val sessionId        = uuid("session_id").references(LiveRunSessions.id)
    val baseXp           = long("base_xp")
    val bonusType        = text("bonus_type")
    val bonusMultiplier  = decimal("bonus_multiplier", 4, 2)
    val bonusXp          = long("bonus_xp")
    val totalXpAwarded   = long("total_xp_awarded")
    val awardedAt        = timestampWithTimeZone("awarded_at")
    val createdAt        = timestampWithTimeZone("created_at")
    val updatedAt        = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)
}

// ---------------------------------------------------------------------------
// Jogging tables -- mirror the public.jogging_sessions and public.route_points
// PostgreSQL tables created by migration 015.
// ---------------------------------------------------------------------------

/**
 * Mirrors the public.jogging_sessions table in Supabase.
 * One row per GPS-tracked jogging workout.
 */
object JoggingSessions : Table("jogging_sessions") {
    val id                   = uuid("id")
    val userId               = uuid("user_id").references(Users.id)
    val liveRunSessionId     = uuid("live_run_session_id").nullable().references(LiveRunSessions.id)
    val startedAt            = timestampWithTimeZone("started_at")
    val endedAt              = timestampWithTimeZone("ended_at").nullable()
    val distanceMeters       = float("distance_meters")
    val durationSeconds      = integer("duration_seconds")
    val avgPaceSecondsPerKm  = integer("avg_pace_seconds_per_km").nullable()
    val caloriesBurned       = integer("calories_burned")
    val earnedTimeCredits    = integer("earned_time_credits")
    val activeDurationSeconds = integer("active_duration_seconds").default(0)
    val pauseDurationSeconds  = integer("pause_duration_seconds").default(0)
    val activeDistanceMeters  = float("active_distance_meters").default(0f)
    val pauseDistanceMeters   = float("pause_distance_meters").default(0f)
    val pauseCount            = integer("pause_count").default(0)
    val createdAt            = timestampWithTimeZone("created_at")
    val updatedAt            = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)

    /**
     * PostgreSQL DATE_TRUNC('day', started_at) expression.
     * Used as GROUP BY key for per-day aggregation.
     */
    val startedAtDay = CustomFunction<java.time.Instant>(
        functionName = "DATE_TRUNC",
        columnType = JavaInstantColumnType(),
        stringParam("day"),
        startedAt,
    )
}

/**
 * Mirrors the public.route_points table in Supabase.
 * GPS breadcrumbs recorded during a jogging session.
 */
object RoutePoints : Table("route_points") {
    val id                  = uuid("id")
    val sessionId           = uuid("session_id").references(JoggingSessions.id)
    val timestamp           = timestampWithTimeZone("timestamp")
    val latitude            = double("latitude")
    val longitude           = double("longitude")
    val altitude            = float("altitude").nullable()
    val speed               = float("speed").nullable()
    val horizontalAccuracy  = float("horizontal_accuracy").nullable()
    val distanceFromStart   = float("distance_from_start")
    val createdAt           = timestampWithTimeZone("created_at")

    override val primaryKey = PrimaryKey(id)
}

/**
 * Mirrors the public.exercise_levels table in Supabase.
 * One row per (user, exercise_type) pair -- tracks accumulated XP per exercise.
 * The current level is derived from [totalXp] on the client via LevelCalculator.
 */
object ExerciseLevels : Table("exercise_levels") {
    val id           = uuid("id")
    val userId       = uuid("user_id").references(Users.id)
    val exerciseType = text("exercise_type")
    val totalXp      = long("total_xp")
    val updatedAt    = timestampWithTimeZone("updated_at")

    override val primaryKey = PrimaryKey(id)

    val idxUserId = Index(
        columns    = listOf(userId),
        unique     = false,
        customName = "idx_exercise_levels_user_id",
    )
}

object JoggingSegments : Table("jogging_segments") {
    val id               = uuid("id")
    val sessionId        = uuid("session_id").references(JoggingSessions.id)
    val segmentType      = text("segment_type")
    val startedAt        = timestampWithTimeZone("started_at")
    val endedAt          = timestampWithTimeZone("ended_at").nullable()
    val distanceMeters   = float("distance_meters")
    val durationSeconds  = integer("duration_seconds")
    val createdAt        = timestampWithTimeZone("created_at")

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

    // Ensure all application tables exist. SchemaUtils.createMissingTablesAndColumns
    // is idempotent -- it only creates tables/columns that are absent and never
    // modifies existing ones. This is a safety net for tables that may not yet
    // exist in the Supabase project (e.g. device_tokens, user_levels, notifications
    // if the numbered migrations were not all applied).
    //
    // NOTE: This does NOT replace the Supabase migrations. RLS policies, triggers,
    // indexes, and enum types are managed exclusively via the migration files.
    // SchemaUtils only handles the raw table structure.
    transaction {
        SchemaUtils.createMissingTablesAndColumns(
            DeviceTokens,
            UserLevels,
            ExerciseLevels,
            Notifications,
            RunEvents,
            LiveRunSessions,
            RunEventParticipants,
            LiveRunParticipants,
            LiveRunPresence,
            RunXpAwards,
            JoggingSessions,
            RoutePoints,
            JoggingSegments,
        )
    }
    log.info("Schema check complete (device_tokens, user_levels, exercise_levels, notifications, social running, jogging_sessions, route_points, jogging_segments tables ensured)")

    return true
}
