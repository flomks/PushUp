package com.pushup.routes

import com.pushup.models.FriendshipResponse
import com.pushup.plugins.JWT_AUTH
import com.pushup.plugins.configureSerialization
import com.pushup.plugins.configureStatusPages
import com.pushup.service.FriendshipService
import com.pushup.service.SendFriendRequestResult
import io.ktor.client.request.bearerAuth
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
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
 * Integration-style tests for POST /api/friends/request.
 *
 * These tests use Ktor's [testApplication] engine with a stub [FriendshipService]
 * so that no real database connection is required.
 */
class FriendRoutesTest {

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
     * - [friendRoutes] wired with the supplied [service]
     */
    private fun withApp(
        service: FriendshipService,
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
                friendRoutes(service, databaseReady = databaseReady)
            }
        }
        val client = createClient {
            // No special config needed
        }
        client.block()
    }

    // -----------------------------------------------------------------------
    // Tests
    // -----------------------------------------------------------------------

    @Test
    fun `returns 401 when no token is provided`() = withApp(FriendshipService()) {
        val response = post("/api/friends/request") {
            contentType(ContentType.Application.Json)
            setBody("""{"receiverId":"${UUID.randomUUID()}"}""")
        }
        assertEquals(HttpStatusCode.Unauthorized, response.status)
    }

    @Test
    fun `returns 503 when database is not ready`() = withApp(FriendshipService(), databaseReady = false) {
        val response = post("/api/friends/request") {
            bearerAuth(buildToken())
            contentType(ContentType.Application.Json)
            setBody("""{"receiverId":"${UUID.randomUUID()}"}""")
        }
        assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
    }

    @Test
    fun `returns 400 when body is missing`() = withApp(FriendshipService()) {
        val response = post("/api/friends/request") {
            bearerAuth(buildToken())
            contentType(ContentType.Application.Json)
            setBody("")
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
    }

    @Test
    fun `returns 400 when receiverId is not a valid UUID`() = withApp(FriendshipService()) {
        val response = post("/api/friends/request") {
            bearerAuth(buildToken())
            contentType(ContentType.Application.Json)
            setBody("""{"receiverId":"not-a-uuid"}""")
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
        assertContains(response.bodyAsText(), "receiverId")
    }

    @Test
    fun `returns 422 when service returns SelfRequest`() {
        val stubService = object : FriendshipService() {
            override suspend fun sendFriendRequest(
                requesterId: UUID,
                receiverId: UUID,
            ): SendFriendRequestResult = SendFriendRequestResult.SelfRequest
        }
        withApp(stubService) {
            val response = post("/api/friends/request") {
                bearerAuth(buildToken())
                contentType(ContentType.Application.Json)
                setBody("""{"receiverId":"${UUID.randomUUID()}"}""")
            }
            assertEquals(HttpStatusCode.UnprocessableEntity, response.status)
            assertContains(response.bodyAsText(), "self_request")
        }
    }

    @Test
    fun `returns 404 when service returns ReceiverNotFound`() {
        val stubService = object : FriendshipService() {
            override suspend fun sendFriendRequest(
                requesterId: UUID,
                receiverId: UUID,
            ): SendFriendRequestResult = SendFriendRequestResult.ReceiverNotFound
        }
        withApp(stubService) {
            val response = post("/api/friends/request") {
                bearerAuth(buildToken())
                contentType(ContentType.Application.Json)
                setBody("""{"receiverId":"${UUID.randomUUID()}"}""")
            }
            assertEquals(HttpStatusCode.NotFound, response.status)
            assertContains(response.bodyAsText(), "receiver_not_found")
        }
    }

    @Test
    fun `returns 409 when service returns AlreadyExists with pending status`() {
        val stubService = object : FriendshipService() {
            override suspend fun sendFriendRequest(
                requesterId: UUID,
                receiverId: UUID,
            ): SendFriendRequestResult = SendFriendRequestResult.AlreadyExists("pending")
        }
        withApp(stubService) {
            val response = post("/api/friends/request") {
                bearerAuth(buildToken())
                contentType(ContentType.Application.Json)
                setBody("""{"receiverId":"${UUID.randomUUID()}"}""")
            }
            assertEquals(HttpStatusCode.Conflict, response.status)
            assertContains(response.bodyAsText(), "already_exists")
        }
    }

    @Test
    fun `returns 409 when service returns AlreadyExists with accepted status`() {
        val stubService = object : FriendshipService() {
            override suspend fun sendFriendRequest(
                requesterId: UUID,
                receiverId: UUID,
            ): SendFriendRequestResult = SendFriendRequestResult.AlreadyExists("accepted")
        }
        withApp(stubService) {
            val response = post("/api/friends/request") {
                bearerAuth(buildToken())
                contentType(ContentType.Application.Json)
                setBody("""{"receiverId":"${UUID.randomUUID()}"}""")
            }
            assertEquals(HttpStatusCode.Conflict, response.status)
            assertContains(response.bodyAsText(), "already friends")
        }
    }

    @Test
    fun `returns 201 with friendship body when service returns Success`() {
        val receiverId = UUID.randomUUID()
        val friendshipId = UUID.randomUUID()
        val stubService = object : FriendshipService() {
            override suspend fun sendFriendRequest(
                requesterId: UUID,
                receiverId: UUID,
            ): SendFriendRequestResult = SendFriendRequestResult.Success(
                FriendshipResponse(
                    id          = friendshipId.toString(),
                    requesterId = requesterId.toString(),
                    receiverId  = receiverId.toString(),
                    status      = "pending",
                    createdAt   = "2026-03-09T12:00:00Z",
                ),
            )
        }
        withApp(stubService) {
            val response = post("/api/friends/request") {
                bearerAuth(buildToken())
                contentType(ContentType.Application.Json)
                setBody("""{"receiverId":"$receiverId"}""")
            }
            assertEquals(HttpStatusCode.Created, response.status)
            val body = response.bodyAsText()
            assertContains(body, friendshipId.toString())
            assertContains(body, "pending")
        }
    }
}
