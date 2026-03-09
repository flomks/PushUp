package com.pushup.routes

import com.pushup.models.MarkReadResponse
import com.pushup.models.NotificationResponse
import com.pushup.models.NotificationsListResponse
import com.pushup.plugins.JWT_AUTH
import com.pushup.plugins.configureSerialization
import com.pushup.plugins.configureStatusPages
import com.pushup.service.MarkNotificationReadResult
import com.pushup.service.NotificationService
import io.ktor.client.request.bearerAuth
import io.ktor.client.request.get
import io.ktor.client.request.patch
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.install
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.jwt.JWTPrincipal
import io.ktor.server.auth.jwt.jwt
import io.ktor.server.routing.routing
import io.ktor.server.testing.testApplication
import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals

/**
 * Integration-style tests for the /api/notifications routes.
 *
 * These tests use Ktor's [testApplication] engine with a stub [NotificationService]
 * so that no real database connection is required.
 */
class NotificationRoutesTest {

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    private val testSecret = "test-secret-at-least-32-chars-long!!"
    private val testUserId = UUID.randomUUID()

    /** Builds a minimal HS256 JWT signed with [testSecret] for [testUserId]. */
    private fun buildToken(userId: UUID = testUserId): String =
        JWT.create()
            .withSubject(userId.toString())
            .withAudience("authenticated")
            .sign(Algorithm.HMAC256(testSecret))

    /**
     * Runs [block] inside a [testApplication] that has:
     * - Serialization configured
     * - Status pages configured
     * - A JWT auth provider backed by [testSecret]
     * - [notificationRoutes] wired with the supplied [service]
     */
    private fun withApp(
        service: NotificationService,
        databaseReady: Boolean = true,
        block: suspend io.ktor.client.HttpClient.() -> Unit,
    ) = testApplication {
        application {
            configureSerialization()
            configureStatusPages()
            install(Authentication) {
                jwt(JWT_AUTH) {
                    verifier(
                        JWT.require(Algorithm.HMAC256(testSecret))
                            .withAudience("authenticated")
                            .build()
                    )
                    validate { credential ->
                        val sub = credential.payload.subject
                        if (sub != null) JWTPrincipal(credential.payload) else null
                    }
                    challenge { _, _ -> }
                }
            }
            routing {
                notificationRoutes(service, databaseReady = databaseReady)
            }
        }
        val client = createClient {}
        client.block()
    }

    // -----------------------------------------------------------------------
    // GET /api/notifications tests
    // -----------------------------------------------------------------------

    @Test
    fun `GET notifications returns 401 when no token is provided`() =
        withApp(NotificationService()) {
            val response = get("/api/notifications")
            assertEquals(HttpStatusCode.Unauthorized, response.status)
        }

    @Test
    fun `GET notifications returns 503 when database is not ready`() =
        withApp(NotificationService(), databaseReady = false) {
            val response = get("/api/notifications") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
        }

    @Test
    fun `GET notifications returns 200 with empty list when no notifications`() {
        val stubService = object : NotificationService() {
            override suspend fun getNotifications(userId: UUID): NotificationsListResponse =
                NotificationsListResponse(
                    notifications = emptyList(),
                    total         = 0,
                    unreadCount   = 0,
                )
        }
        withApp(stubService) {
            val response = get("/api/notifications") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            assertContains(body, "\"notifications\"")
            assertContains(body, "\"total\"")
            assertContains(body, "\"unreadCount\"")
        }
    }

    @Test
    fun `GET notifications returns 200 with notifications list`() {
        val notificationId = UUID.randomUUID()
        val actorId        = UUID.randomUUID()
        val stubService = object : NotificationService() {
            override suspend fun getNotifications(userId: UUID): NotificationsListResponse =
                NotificationsListResponse(
                    notifications = listOf(
                        NotificationResponse(
                            id        = notificationId.toString(),
                            type      = "friend_request",
                            actorId   = actorId.toString(),
                            actorName = "Alice Smith",
                            payload   = """{"friendship_id":"some-uuid"}""",
                            isRead    = false,
                            createdAt = "2026-03-09T12:00:00Z",
                        ),
                    ),
                    total       = 1,
                    unreadCount = 1,
                )
        }
        withApp(stubService) {
            val response = get("/api/notifications") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            assertContains(body, notificationId.toString())
            assertContains(body, "friend_request")
            assertContains(body, "Alice Smith")
            assertContains(body, "\"unreadCount\"")
        }
    }

    @Test
    fun `GET notifications passes correct userId to service`() {
        var capturedUserId: UUID? = null
        val stubService = object : NotificationService() {
            override suspend fun getNotifications(userId: UUID): NotificationsListResponse {
                capturedUserId = userId
                return NotificationsListResponse(emptyList(), 0, 0)
            }
        }
        withApp(stubService) {
            get("/api/notifications") {
                bearerAuth(buildToken(testUserId))
            }
            assertEquals(testUserId, capturedUserId)
        }
    }

    // -----------------------------------------------------------------------
    // PATCH /api/notifications/{id}/read tests
    // -----------------------------------------------------------------------

    @Test
    fun `PATCH read returns 401 when no token is provided`() =
        withApp(NotificationService()) {
            val response = patch("/api/notifications/${UUID.randomUUID()}/read")
            assertEquals(HttpStatusCode.Unauthorized, response.status)
        }

    @Test
    fun `PATCH read returns 503 when database is not ready`() =
        withApp(NotificationService(), databaseReady = false) {
            val response = patch("/api/notifications/${UUID.randomUUID()}/read") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
        }

    @Test
    fun `PATCH read returns 400 when id is not a valid UUID`() =
        withApp(NotificationService()) {
            val response = patch("/api/notifications/not-a-uuid/read") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.BadRequest, response.status)
            assertContains(response.bodyAsText(), "bad_request")
        }

    @Test
    fun `PATCH read returns 404 when service returns NotFound`() {
        val stubService = object : NotificationService() {
            override suspend fun markNotificationRead(
                userId: UUID,
                notificationId: UUID,
            ): MarkNotificationReadResult = MarkNotificationReadResult.NotFound
        }
        withApp(stubService) {
            val response = patch("/api/notifications/${UUID.randomUUID()}/read") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.NotFound, response.status)
            assertContains(response.bodyAsText(), "not_found")
        }
    }

    @Test
    fun `PATCH read returns 200 with updatedCount when service returns Success`() {
        val stubService = object : NotificationService() {
            override suspend fun markNotificationRead(
                userId: UUID,
                notificationId: UUID,
            ): MarkNotificationReadResult =
                MarkNotificationReadResult.Success(MarkReadResponse(updatedCount = 1))
        }
        withApp(stubService) {
            val response = patch("/api/notifications/${UUID.randomUUID()}/read") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            assertContains(response.bodyAsText(), "\"updatedCount\"")
        }
    }

    // -----------------------------------------------------------------------
    // PATCH /api/notifications/read-all tests
    // -----------------------------------------------------------------------

    @Test
    fun `PATCH read-all returns 401 when no token is provided`() =
        withApp(NotificationService()) {
            val response = patch("/api/notifications/read-all")
            assertEquals(HttpStatusCode.Unauthorized, response.status)
        }

    @Test
    fun `PATCH read-all returns 503 when database is not ready`() =
        withApp(NotificationService(), databaseReady = false) {
            val response = patch("/api/notifications/read-all") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
        }

    @Test
    fun `PATCH read-all returns 200 with updatedCount`() {
        val stubService = object : NotificationService() {
            override suspend fun markAllNotificationsRead(userId: UUID): MarkReadResponse =
                MarkReadResponse(updatedCount = 3)
        }
        withApp(stubService) {
            val response = patch("/api/notifications/read-all") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            assertContains(response.bodyAsText(), "\"updatedCount\"")
        }
    }

    @Test
    fun `PATCH read-all returns 200 with zero when no unread notifications`() {
        val stubService = object : NotificationService() {
            override suspend fun markAllNotificationsRead(userId: UUID): MarkReadResponse =
                MarkReadResponse(updatedCount = 0)
        }
        withApp(stubService) {
            val response = patch("/api/notifications/read-all") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            assertContains(response.bodyAsText(), "\"updatedCount\"")
        }
    }
}
