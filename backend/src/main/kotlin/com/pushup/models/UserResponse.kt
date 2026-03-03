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

/**
 * Generic error response body used across all endpoints.
 */
@Serializable
data class ErrorResponse(
    val error: String,
    val message: String? = null,
)

/**
 * Response body returned by GET /health.
 */
@Serializable
data class HealthResponse(
    val status: String,
)
