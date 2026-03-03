package com.pushup.models

import kotlinx.serialization.Serializable

/**
 * Response body returned by GET /api/me.
 */
@Serializable
data class UserResponse(
    val id: String,
    val email: String,
    val displayName: String?,
    val avatarUrl: String?,
    val createdAt: String,
    val updatedAt: String,
)
