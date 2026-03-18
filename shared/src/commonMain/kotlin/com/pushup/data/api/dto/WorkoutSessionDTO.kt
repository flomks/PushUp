package com.pushup.data.api.dto

import com.pushup.domain.model.PushUpRecord
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.WorkoutSession
import kotlinx.datetime.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// =============================================================================
// WorkoutSession DTOs
// =============================================================================

/**
 * DTO for a workout session as returned by the Supabase REST API.
 *
 * Column names follow the Supabase/PostgreSQL snake_case convention and are
 * mapped via [SerialName] annotations. All timestamps are ISO-8601 strings
 * (Supabase returns `timestamptz` values in this format).
 *
 * @property id                    UUID of the session.
 * @property userId                UUID of the owning user.
 * @property startedAt             ISO-8601 timestamp when the session started.
 * @property endedAt               ISO-8601 timestamp when the session ended, or `null`.
 * @property pushUpCount           Total push-ups counted in this session.
 * @property earnedTimeCredits     Screen-time credits earned (seconds).
 * @property quality               Average form quality score (0.0 - 1.0).
 * @property createdAt             ISO-8601 timestamp of row creation (server-managed).
 * @property updatedAt             ISO-8601 timestamp of last update (server-managed).
 */
@Serializable
data class WorkoutSessionDTO(
    @SerialName("id")                   val id: String,
    @SerialName("user_id")              val userId: String,
    @SerialName("started_at")           val startedAt: String,
    @SerialName("ended_at")             val endedAt: String? = null,
    @SerialName("push_up_count")        val pushUpCount: Int,
    @SerialName("earned_time_credits")  val earnedTimeCredits: Int,
    @SerialName("quality")              val quality: Float,
    @SerialName("created_at")           val createdAt: String? = null,
    @SerialName("updated_at")           val updatedAt: String? = null,
)

/**
 * Request body for creating a new workout session via the Supabase REST API.
 *
 * Only the fields that the client provides on creation are included.
 * Server-managed fields (`id`, `created_at`, `updated_at`) are omitted --
 * Supabase generates them automatically.
 */
@Serializable
data class CreateWorkoutSessionRequest(
    @SerialName("user_id")              val userId: String,
    @SerialName("started_at")           val startedAt: String,
    @SerialName("ended_at")             val endedAt: String? = null,
    @SerialName("push_up_count")        val pushUpCount: Int = 0,
    @SerialName("earned_time_credits")  val earnedTimeCredits: Int = 0,
    @SerialName("quality")              val quality: Float = 0f,
)

/**
 * Request body for updating an existing workout session.
 *
 * All fields are optional (`null` means "do not change this field").
 * The Supabase PATCH endpoint only updates the columns that are present
 * in the request body.
 */
@Serializable
data class UpdateWorkoutSessionRequest(
    @SerialName("ended_at")             val endedAt: String? = null,
    @SerialName("push_up_count")        val pushUpCount: Int? = null,
    @SerialName("earned_time_credits")  val earnedTimeCredits: Int? = null,
    @SerialName("quality")              val quality: Float? = null,
)

// =============================================================================
// PushUpRecord DTOs
// =============================================================================

/**
 * DTO for a single push-up record as returned by the Supabase REST API.
 *
 * @property id          UUID of the record.
 * @property sessionId   UUID of the parent workout session.
 * @property timestamp   ISO-8601 timestamp of the push-up detection.
 * @property durationMs  Duration of the push-up movement in milliseconds.
 * @property depthScore  How deep the push-up was (0.0 - 1.0).
 * @property formScore   Form quality score (0.0 - 1.0).
 * @property createdAt   ISO-8601 timestamp of row creation (server-managed).
 */
@Serializable
data class PushUpRecordDTO(
    @SerialName("id")           val id: String,
    @SerialName("session_id")   val sessionId: String,
    @SerialName("timestamp")    val timestamp: String,
    @SerialName("duration_ms")  val durationMs: Long? = null,
    @SerialName("depth_score")  val depthScore: Float? = null,
    @SerialName("form_score")   val formScore: Float? = null,
    @SerialName("created_at")   val createdAt: String? = null,
)

/**
 * Request body for inserting a new push-up record.
 */
@Serializable
data class CreatePushUpRecordRequest(
    @SerialName("session_id")   val sessionId: String,
    @SerialName("timestamp")    val timestamp: String,
    @SerialName("duration_ms")  val durationMs: Long,
    @SerialName("depth_score")  val depthScore: Float,
    @SerialName("form_score")   val formScore: Float,
)

// =============================================================================
// TimeCredit DTOs
// =============================================================================

/**
 * DTO for the time_credits row as returned by the Supabase REST API.
 *
 * There is exactly one row per user (UNIQUE on user_id).
 *
 * @property id                   UUID of the record.
 * @property userId               UUID of the owning user.
 * @property totalEarnedSeconds   Cumulative seconds earned through workouts.
 * @property totalSpentSeconds    Cumulative seconds consumed as screen time.
 * @property dailyEarnedSeconds   Credits available in the current daily period (earned + carry-over).
 * @property dailySpentSeconds    Credits spent in the current daily period.
 * @property lastResetAt          ISO-8601 timestamp of the most recent daily reset, or null.
 * @property updatedAt            ISO-8601 timestamp of last update.
 */
@Serializable
data class TimeCreditDTO(
    @SerialName("id")                     val id: String,
    @SerialName("user_id")                val userId: String,
    @SerialName("total_earned_seconds")   val totalEarnedSeconds: Long,
    @SerialName("total_spent_seconds")    val totalSpentSeconds: Long,
    @SerialName("daily_earned_seconds")   val dailyEarnedSeconds: Long? = null,
    @SerialName("daily_spent_seconds")    val dailySpentSeconds: Long? = null,
    @SerialName("last_reset_at")          val lastResetAt: String? = null,
    @SerialName("updated_at")             val updatedAt: String? = null,
)

/**
 * Request body for upserting the time_credits row.
 *
 * Supabase PATCH is used for partial updates (only the fields that changed).
 */
@Serializable
data class UpdateTimeCreditRequest(
    @SerialName("total_earned_seconds")   val totalEarnedSeconds: Long? = null,
    @SerialName("total_spent_seconds")    val totalSpentSeconds: Long? = null,
    @SerialName("daily_earned_seconds")   val dailyEarnedSeconds: Long? = null,
    @SerialName("daily_spent_seconds")    val dailySpentSeconds: Long? = null,
    @SerialName("last_reset_at")          val lastResetAt: String? = null,
)

// =============================================================================
// UserProfile DTO
// =============================================================================

/**
 * DTO for the public.users row as returned by the Supabase REST API.
 *
 * Only the fields relevant for sync are included here.
 *
 * @property id                UUID of the user.
 * @property username          The user's unique handle (may be null if not yet set).
 * @property displayName       The user's display name (may be null if not yet set).
 * @property email             The user's email address.
 * @property avatarUrl         OAuth provider avatar URL (Google/Apple).
 * @property customAvatarUrl   User-uploaded avatar URL (takes priority over avatarUrl).
 * @property avatarVisibility  Who can see the avatar: 'everyone', 'friends_only', 'nobody'.
 * @property updatedAt         ISO-8601 timestamp of last update (server-managed).
 */
@Serializable
data class UserProfileDTO(
    @SerialName("id")                  val id: String,
    @SerialName("username")            val username: String? = null,
    @SerialName("display_name")        val displayName: String? = null,
    @SerialName("email")               val email: String? = null,
    @SerialName("avatar_url")          val avatarUrl: String? = null,
    @SerialName("custom_avatar_url")   val customAvatarUrl: String? = null,
    @SerialName("avatar_visibility")   val avatarVisibility: String? = null,
    @SerialName("updated_at")          val updatedAt: String? = null,
) {
    /** Returns the effective avatar URL: custom takes priority over OAuth. */
    val effectiveAvatarUrl: String? get() = customAvatarUrl ?: avatarUrl
}

/**
 * Request body for updating the user's display name in public.users.
 */
@Serializable
data class UpdateUserProfileRequest(
    @SerialName("display_name") val displayName: String,
)

/**
 * Request body for setting the user's username via the Ktor backend.
 */
@Serializable
data class SetUsernameRequest(
    @SerialName("username") val username: String,
)

/**
 * Response body returned by the username check endpoint.
 */
@Serializable
data class UsernameCheckResponse(
    @SerialName("username")  val username: String,
    @SerialName("available") val available: Boolean,
)

/**
 * Response body returned by the set-username endpoint.
 */
@Serializable
data class SetUsernameResponse(
    @SerialName("username") val username: String,
)

// =============================================================================
// UserLevel DTOs
// =============================================================================

/**
 * DTO for the user_levels row as returned by the Supabase REST API.
 *
 * There is exactly one row per user (UNIQUE on user_id).
 *
 * @property id           UUID of the record.
 * @property userId       UUID of the owning user.
 * @property totalXp      Total XP accumulated across all time.
 * @property updatedAt    ISO-8601 timestamp of last update.
 */
@Serializable
data class UserLevelDTO(
    @SerialName("id")          val id: String,
    @SerialName("user_id")     val userId: String,
    @SerialName("total_xp")    val totalXp: Long,
    @SerialName("updated_at")  val updatedAt: String? = null,
)

/**
 * Request body for upserting the user_levels row.
 *
 * Uses Supabase upsert (POST with Prefer: resolution=merge-duplicates) so that
 * the row is created on first sync and updated on subsequent syncs.
 */
@Serializable
data class UpsertUserLevelRequest(
    @SerialName("user_id")     val userId: String,
    @SerialName("total_xp")    val totalXp: Long,
)

// =============================================================================
// Domain model mappers
// =============================================================================

/**
 * Converts a [WorkoutSessionDTO] received from the Supabase REST API into
 * a [WorkoutSession] domain model.
 *
 * The [syncStatus] is always [SyncStatus.SYNCED] because the data came
 * directly from the server.
 */
fun WorkoutSessionDTO.toDomain(): WorkoutSession = WorkoutSession(
    id = id,
    userId = userId,
    startedAt = Instant.parse(startedAt),
    endedAt = endedAt?.let { Instant.parse(it) },
    pushUpCount = pushUpCount,
    earnedTimeCreditSeconds = earnedTimeCredits.toLong(),
    quality = quality,
    syncStatus = SyncStatus.SYNCED,
)

/**
 * Converts a [WorkoutSession] domain model into a [CreateWorkoutSessionRequest]
 * suitable for the Supabase REST API POST endpoint.
 */
fun WorkoutSession.toCreateRequest(): CreateWorkoutSessionRequest = CreateWorkoutSessionRequest(
    userId = userId,
    startedAt = startedAt.toString(),
    endedAt = endedAt?.toString(),
    pushUpCount = pushUpCount,
    earnedTimeCredits = earnedTimeCreditSeconds.toInt(),
    quality = quality,
)

/**
 * Converts a [PushUpRecordDTO] received from the Supabase REST API into
 * a [PushUpRecord] domain model.
 */
fun PushUpRecordDTO.toDomain(): PushUpRecord = PushUpRecord(
    id = id,
    sessionId = sessionId,
    timestamp = Instant.parse(timestamp),
    durationMs = durationMs ?: 0L,
    depthScore = depthScore ?: 0f,
    formScore = formScore ?: 0f,
)

/**
 * Converts a [PushUpRecord] domain model into a [CreatePushUpRecordRequest]
 * suitable for the Supabase REST API POST endpoint.
 */
fun PushUpRecord.toCreateRequest(): CreatePushUpRecordRequest = CreatePushUpRecordRequest(
    sessionId = sessionId,
    timestamp = timestamp.toString(),
    durationMs = durationMs,
    depthScore = depthScore,
    formScore = formScore,
)
