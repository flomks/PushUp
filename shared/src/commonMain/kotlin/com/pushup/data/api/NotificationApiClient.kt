package com.pushup.data.api

import com.pushup.data.api.dto.MarkReadResponseDTO
import com.pushup.data.api.dto.NotificationsListDTO
import com.pushup.data.api.dto.toDomain
import com.pushup.domain.model.AppNotification
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.patch

/**
 * HTTP client for the notifications endpoints of the Ktor backend.
 *
 * ## Endpoints
 * | Method | Path                                    | Description                              |
 * |--------|-----------------------------------------|------------------------------------------|
 * | GET    | /api/notifications                      | List all notifications for the caller    |
 * | PATCH  | /api/notifications/{id}/read            | Mark a single notification as read       |
 * | PATCH  | /api/notifications/read-all             | Mark all notifications as read           |
 *
 * ## Authentication
 * Every request includes `Authorization: Bearer <jwt>`. The token is fetched
 * lazily via [tokenProvider] on every call so it is always fresh.
 *
 * @property httpClient     Configured [HttpClient] (from [createHttpClient]).
 * @property backendBaseUrl Ktor backend base URL, e.g. `https://api.pushup.com`.
 * @property tokenProvider  Returns the current JWT access token.
 * @property maxRetries     Max retry attempts for transient errors (default 3).
 */
class NotificationApiClient(
    private val httpClient: HttpClient,
    private val backendBaseUrl: String,
    private val tokenProvider: suspend () -> String,
    maxRetries: Int = 3,
) : ApiClientBase(maxRetries) {

    /**
     * Returns all in-app notifications for the authenticated user, ordered
     * by creation time descending (newest first).
     *
     * Calls `GET /api/notifications`.
     *
     * @return List of [AppNotification]s.
     */
    suspend fun getNotifications(): List<AppNotification> = withRetry {
        val token = tokenProvider()
        httpClient.get("$backendBaseUrl/api/notifications") {
            bearerAuth(token)
        }.also { it.expectSuccess() }
            .body<NotificationsListDTO>()
            .notifications
            .map { it.toDomain() }
    }

    /**
     * Marks a single notification as read.
     *
     * Calls `PATCH /api/notifications/{notificationId}/read`.
     *
     * @param notificationId UUID of the notification to mark as read.
     * @return Number of notifications updated (0 or 1).
     */
    suspend fun markNotificationRead(notificationId: String): Int {
        require(UUID_REGEX.matches(notificationId)) {
            "notificationId must be a valid UUID, got: $notificationId"
        }
        return withRetry {
            val token = tokenProvider()
            httpClient.patch("$backendBaseUrl/api/notifications/$notificationId/read") {
                bearerAuth(token)
            }.also { it.expectSuccess() }
                .body<MarkReadResponseDTO>()
                .updatedCount
        }
    }

    /**
     * Marks all unread notifications for the authenticated user as read.
     *
     * Calls `PATCH /api/notifications/read-all`.
     *
     * @return Number of notifications updated.
     */
    suspend fun markAllNotificationsRead(): Int = withRetry {
        val token = tokenProvider()
        httpClient.patch("$backendBaseUrl/api/notifications/read-all") {
            bearerAuth(token)
        }.also { it.expectSuccess() }
            .body<MarkReadResponseDTO>()
            .updatedCount
    }

    companion object {
        /**
         * Regex for validating UUID v4 format before interpolating into URL paths.
         */
        private val UUID_REGEX = Regex(
            "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        )
    }
}
