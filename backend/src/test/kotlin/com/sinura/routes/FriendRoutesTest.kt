package com.sinura.routes

import com.sinura.models.FriendProfile
import com.sinura.models.FriendshipResponse
import com.sinura.models.FriendsListResponse
import com.sinura.plugins.FriendshipStatus
import com.sinura.plugins.JWT_AUTH
import com.sinura.plugins.configureSerialization
import com.sinura.plugins.configureStatusPages
import com.sinura.service.FriendListFilter
import com.sinura.service.FriendshipService
import com.sinura.service.RespondFriendRequestResult
import com.sinura.service.SendFriendRequestResult
import io.ktor.client.request.bearerAuth
import io.ktor.client.request.get
import io.ktor.client.request.patch
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

    // -----------------------------------------------------------------------
    // PATCH /api/friends/request/{id} tests
    // -----------------------------------------------------------------------

    @Test
    fun `PATCH returns 401 when no token is provided`() = withApp(FriendshipService()) {
        val response = patch("/api/friends/request/${UUID.randomUUID()}") {
            contentType(ContentType.Application.Json)
            setBody("""{"status":"accepted"}""")
        }
        assertEquals(HttpStatusCode.Unauthorized, response.status)
    }

    @Test
    fun `PATCH returns 503 when database is not ready`() = withApp(FriendshipService(), databaseReady = false) {
        val response = patch("/api/friends/request/${UUID.randomUUID()}") {
            bearerAuth(buildToken())
            contentType(ContentType.Application.Json)
            setBody("""{"status":"accepted"}""")
        }
        assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
    }

    @Test
    fun `PATCH returns 400 when id is not a valid UUID`() = withApp(FriendshipService()) {
        val response = patch("/api/friends/request/not-a-uuid") {
            bearerAuth(buildToken())
            contentType(ContentType.Application.Json)
            setBody("""{"status":"accepted"}""")
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
        assertContains(response.bodyAsText(), "bad_request")
    }

    @Test
    fun `PATCH returns 400 when body is missing`() = withApp(FriendshipService()) {
        val response = patch("/api/friends/request/${UUID.randomUUID()}") {
            bearerAuth(buildToken())
            contentType(ContentType.Application.Json)
            setBody("")
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
    }

    @Test
    fun `PATCH returns 400 when status value is invalid`() = withApp(FriendshipService()) {
        val response = patch("/api/friends/request/${UUID.randomUUID()}") {
            bearerAuth(buildToken())
            contentType(ContentType.Application.Json)
            setBody("""{"status":"pending"}""")
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
        assertContains(response.bodyAsText(), "bad_request")
    }

    @Test
    fun `PATCH returns 404 when service returns NotFound`() {
        val stubService = object : FriendshipService() {
            override suspend fun respondToFriendRequest(
                callerId: UUID,
                friendshipId: UUID,
                newStatus: FriendshipStatus,
            ): RespondFriendRequestResult = RespondFriendRequestResult.NotFound
        }
        withApp(stubService) {
            val response = patch("/api/friends/request/${UUID.randomUUID()}") {
                bearerAuth(buildToken())
                contentType(ContentType.Application.Json)
                setBody("""{"status":"accepted"}""")
            }
            assertEquals(HttpStatusCode.NotFound, response.status)
            assertContains(response.bodyAsText(), "not_found")
        }
    }

    @Test
    fun `PATCH returns 401 when service returns Forbidden`() {
        val stubService = object : FriendshipService() {
            override suspend fun respondToFriendRequest(
                callerId: UUID,
                friendshipId: UUID,
                newStatus: FriendshipStatus,
            ): RespondFriendRequestResult = RespondFriendRequestResult.Forbidden
        }
        withApp(stubService) {
            val response = patch("/api/friends/request/${UUID.randomUUID()}") {
                bearerAuth(buildToken())
                contentType(ContentType.Application.Json)
                setBody("""{"status":"accepted"}""")
            }
            assertEquals(HttpStatusCode.Unauthorized, response.status)
            assertContains(response.bodyAsText(), "unauthorized")
        }
    }

    @Test
    fun `PATCH returns 409 when service returns AlreadyResponded`() {
        val stubService = object : FriendshipService() {
            override suspend fun respondToFriendRequest(
                callerId: UUID,
                friendshipId: UUID,
                newStatus: FriendshipStatus,
            ): RespondFriendRequestResult = RespondFriendRequestResult.AlreadyResponded("accepted")
        }
        withApp(stubService) {
            val response = patch("/api/friends/request/${UUID.randomUUID()}") {
                bearerAuth(buildToken())
                contentType(ContentType.Application.Json)
                setBody("""{"status":"declined"}""")
            }
            assertEquals(HttpStatusCode.Conflict, response.status)
            assertContains(response.bodyAsText(), "already_responded")
        }
    }

    @Test
    fun `PATCH returns 200 with updated friendship when accepted`() {
        val friendshipId = UUID.randomUUID()
        val requesterId  = UUID.randomUUID()
        val stubService = object : FriendshipService() {
            override suspend fun respondToFriendRequest(
                callerId: UUID,
                friendshipId: UUID,
                newStatus: FriendshipStatus,
            ): RespondFriendRequestResult = RespondFriendRequestResult.Success(
                FriendshipResponse(
                    id          = friendshipId.toString(),
                    requesterId = requesterId.toString(),
                    receiverId  = callerId.toString(),
                    status      = "accepted",
                    createdAt   = "2026-03-09T12:00:00Z",
                ),
            )
        }
        withApp(stubService) {
            val response = patch("/api/friends/request/$friendshipId") {
                bearerAuth(buildToken())
                contentType(ContentType.Application.Json)
                setBody("""{"status":"accepted"}""")
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            assertContains(body, friendshipId.toString())
            assertContains(body, "accepted")
        }
    }

    @Test
    fun `PATCH returns 200 with updated friendship when declined`() {
        val friendshipId = UUID.randomUUID()
        val requesterId  = UUID.randomUUID()
        val stubService = object : FriendshipService() {
            override suspend fun respondToFriendRequest(
                callerId: UUID,
                friendshipId: UUID,
                newStatus: FriendshipStatus,
            ): RespondFriendRequestResult = RespondFriendRequestResult.Success(
                FriendshipResponse(
                    id          = friendshipId.toString(),
                    requesterId = requesterId.toString(),
                    receiverId  = callerId.toString(),
                    status      = "declined",
                    createdAt   = "2026-03-09T12:00:00Z",
                ),
            )
        }
        withApp(stubService) {
            val response = patch("/api/friends/request/$friendshipId") {
                bearerAuth(buildToken())
                contentType(ContentType.Application.Json)
                setBody("""{"status":"declined"}""")
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            assertContains(body, friendshipId.toString())
            assertContains(body, "declined")
        }
    }

    // -----------------------------------------------------------------------
    // GET /api/friends tests
    // -----------------------------------------------------------------------

    @Test
    fun `GET friends returns 401 when no token is provided`() = withApp(FriendshipService()) {
        val response = get("/api/friends")
        assertEquals(HttpStatusCode.Unauthorized, response.status)
    }

    @Test
    fun `GET friends returns 503 when database is not ready`() =
        withApp(FriendshipService(), databaseReady = false) {
            val response = get("/api/friends") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
        }

    @Test
    fun `GET friends returns 400 for unknown status parameter`() = withApp(FriendshipService()) {
        val response = get("/api/friends?status=unknown") {
            bearerAuth(buildToken())
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
        assertContains(response.bodyAsText(), "bad_request")
    }

    @Test
    fun `GET friends returns 200 with empty list when no accepted friends`() {
        val stubService = object : FriendshipService() {
            override suspend fun getFriends(
                userId: UUID,
                filter: FriendListFilter,
            ): FriendsListResponse = FriendsListResponse(friends = emptyList(), total = 0)
        }
        withApp(stubService) {
            val response = get("/api/friends") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            assertContains(body, "\"friends\"")
            assertContains(body, "\"total\"")
        }
    }

    @Test
    fun `GET friends returns 200 with accepted friends by default`() {
        val friendId = UUID.randomUUID()
        val stubService = object : FriendshipService() {
            override suspend fun getFriends(
                userId: UUID,
                filter: FriendListFilter,
            ): FriendsListResponse {
                assertEquals(FriendListFilter.ACCEPTED, filter)
                return FriendsListResponse(
                    friends = listOf(
                        FriendProfile(
                            id          = friendId.toString(),
                            username    = "jane_doe",
                            displayName = "Jane Doe",
                            avatarUrl   = "https://example.com/avatar.png",
                        ),
                    ),
                    total = 1,
                )
            }
        }
        withApp(stubService) {
            val response = get("/api/friends") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            assertContains(body, friendId.toString())
            assertContains(body, "jane_doe")
            assertContains(body, "Jane Doe")
            assertContains(body, "\"total\"")
        }
    }

    @Test
    fun `GET friends returns 200 with accepted friends when status=accepted`() {
        val friendId = UUID.randomUUID()
        val stubService = object : FriendshipService() {
            override suspend fun getFriends(
                userId: UUID,
                filter: FriendListFilter,
            ): FriendsListResponse {
                assertEquals(FriendListFilter.ACCEPTED, filter)
                return FriendsListResponse(
                    friends = listOf(
                        FriendProfile(
                            id          = friendId.toString(),
                            username    = "alice",
                            displayName = "Alice",
                            avatarUrl   = null,
                        ),
                    ),
                    total = 1,
                )
            }
        }
        withApp(stubService) {
            val response = get("/api/friends?status=accepted") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            assertContains(response.bodyAsText(), friendId.toString())
        }
    }

    @Test
    fun `GET friends returns 200 with incoming pending requests when status=incoming`() {
        val senderId = UUID.randomUUID()
        val stubService = object : FriendshipService() {
            override suspend fun getFriends(
                userId: UUID,
                filter: FriendListFilter,
            ): FriendsListResponse {
                assertEquals(FriendListFilter.INCOMING, filter)
                return FriendsListResponse(
                    friends = listOf(
                        FriendProfile(
                            id          = senderId.toString(),
                            username    = "bob",
                            displayName = "Bob",
                            avatarUrl   = null,
                        ),
                    ),
                    total = 1,
                )
            }
        }
        withApp(stubService) {
            val response = get("/api/friends?status=incoming") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            assertContains(body, senderId.toString())
            assertContains(body, "bob")
        }
    }

    @Test
    fun `GET friends returns 200 with outgoing pending requests when status=outgoing`() {
        val receiverId = UUID.randomUUID()
        val stubService = object : FriendshipService() {
            override suspend fun getFriends(
                userId: UUID,
                filter: FriendListFilter,
            ): FriendsListResponse {
                assertEquals(FriendListFilter.OUTGOING, filter)
                return FriendsListResponse(
                    friends = listOf(
                        FriendProfile(
                            id          = receiverId.toString(),
                            username    = "charlie",
                            displayName = "Charlie",
                            avatarUrl   = "https://example.com/charlie.png",
                        ),
                    ),
                    total = 1,
                )
            }
        }
        withApp(stubService) {
            val response = get("/api/friends?status=outgoing") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            assertContains(body, receiverId.toString())
            assertContains(body, "charlie")
        }
    }

    @Test
    fun `GET friends response includes all required profile fields`() {
        val friendId = UUID.randomUUID()
        val stubService = object : FriendshipService() {
            override suspend fun getFriends(
                userId: UUID,
                filter: FriendListFilter,
            ): FriendsListResponse = FriendsListResponse(
                friends = listOf(
                    FriendProfile(
                        id          = friendId.toString(),
                        username    = "dave",
                        displayName = "Dave Smith",
                        avatarUrl   = "https://example.com/dave.jpg",
                    ),
                ),
                total = 1,
            )
        }
        withApp(stubService) {
            val response = get("/api/friends") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            // Verify all four required profile fields are present in the response
            assertContains(body, "\"id\"")
            assertContains(body, "\"username\"")
            assertContains(body, "\"displayName\"")
            assertContains(body, "\"avatarUrl\"")
            assertContains(body, friendId.toString())
            assertContains(body, "dave")
            assertContains(body, "Dave Smith")
            assertContains(body, "https://example.com/dave.jpg")
        }
    }

    @Test
    fun `GET friends handles null optional profile fields`() {
        val friendId = UUID.randomUUID()
        val stubService = object : FriendshipService() {
            override suspend fun getFriends(
                userId: UUID,
                filter: FriendListFilter,
            ): FriendsListResponse = FriendsListResponse(
                friends = listOf(
                    FriendProfile(
                        id          = friendId.toString(),
                        username    = null,
                        displayName = null,
                        avatarUrl   = null,
                    ),
                ),
                total = 1,
            )
        }
        withApp(stubService) {
            val response = get("/api/friends") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            assertContains(body, friendId.toString())
            assertContains(body, "\"total\"")
        }
    }
}
