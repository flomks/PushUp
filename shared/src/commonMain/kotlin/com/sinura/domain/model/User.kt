package com.sinura.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

/**
 * Controls who can see a user's avatar image.
 *
 * Mirrors the `avatar_visibility` PostgreSQL enum in Supabase.
 */
@Serializable
enum class AvatarVisibility {
    /** Default: any authenticated user can see the avatar. */
    EVERYONE,
    /** Only accepted friends can see the avatar. */
    FRIENDS_ONLY,
    /** Avatar is hidden for everyone; initials are shown instead. */
    NOBODY;

    /** Returns the lowercase string stored in the database enum column. */
    fun toDbValue(): String = name.lowercase()

    companion object {
        fun fromDbValue(value: String): AvatarVisibility =
            entries.firstOrNull { it.name.equals(value, ignoreCase = true) }
                ?: EVERYONE
    }
}

/**
 * Represents an authenticated user of the PushUp application.
 *
 * All properties are immutable; create a new instance via [copy] to reflect changes.
 *
 * @property id               Unique identifier for the user.
 * @property email            The user's email address.
 * @property username         Unique handle chosen by the user (e.g. "john_doe").
 *                            Null until the user completes the username setup screen.
 * @property displayName      Human-readable display name.
 * @property avatarUrl        The effective avatar URL to display. This is the
 *                            resolved value: custom_avatar_url if set, otherwise
 *                            the OAuth provider avatar_url. Null if no avatar.
 * @property avatarVisibility Who can see this user's avatar.
 * @property createdAt        Timestamp when the user account was created.
 * @property lastSyncedAt     Timestamp of the last successful data synchronization.
 */
@Serializable
data class User(
    val id: String,
    val email: String,
    val username: String? = null,
    val displayName: String,
    val avatarUrl: String? = null,
    val avatarVisibility: AvatarVisibility = AvatarVisibility.EVERYONE,
    val createdAt: Instant,
    val lastSyncedAt: Instant,
) {
    init {
        require(id.isNotBlank()) { "User.id must not be blank" }
        require(email.isNotBlank()) { "User.email must not be blank" }
        require(displayName.isNotBlank()) { "User.displayName must not be blank" }
    }
}
