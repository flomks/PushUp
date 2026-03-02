package com.pushup.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

/**
 * Represents an authenticated user of the PushUp application.
 *
 * All properties are immutable; create a new instance via [copy] to reflect changes.
 *
 * @property id Unique identifier for the user.
 * @property email The user's email address.
 * @property displayName Human-readable display name.
 * @property createdAt Timestamp when the user account was created.
 * @property lastSyncedAt Timestamp of the last successful data synchronization with the server.
 */
@Serializable
data class User(
    val id: String,
    val email: String,
    val displayName: String,
    val createdAt: Instant,
    val lastSyncedAt: Instant,
) {
    init {
        require(id.isNotBlank()) { "User.id must not be blank" }
        require(email.isNotBlank()) { "User.email must not be blank" }
        require(displayName.isNotBlank()) { "User.displayName must not be blank" }
    }
}
