package com.sinura.routes

import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import com.sinura.models.FriendshipStatusResponse
import com.sinura.models.UserSearchResponse
import com.sinura.models.UserSearchResult
import com.sinura.plugins.JWT_AUTH
import com.sinura.plugins.configureSerialization
import com.sinura.plugins.configureStatusPages
import com.sinura.service.UserSearchService
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.install
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.jwt.JWTPrincipal
import io.ktor.server.auth.jwt.jwt
import io.ktor.server.routing.routing
import io.ktor.server.testing.testApplication
import kotlinx.serialization.json.Json
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Unit tests for the GET /v1/users/search route handler.
 *
 * These tests exercise the HTTP layer in isolation using Ktor's [testApplication]
 * harness.  The [UserSearchService] is replaced with a test double so no real
 * database is required.
 *
 * Covered scenarios:
 *   - Missing query parameter returns 400
 *   - Empty query parameter returns 400
 *   - Query shorter than minimum length returns 400
 *   - Valid query with databaseReady=false returns 503
 *   - Valid query returns 200 with the service result
 *   - Service result is correctly serialised (friendshipStatus values)
 */
class UserSearchRoutesTest {

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    private val testUserId = UUID.fromString("00000000-0000-0000-0000-000000000001")
    private val jwtSecret = "test-secret-for-unit-tests"

    /** Generates a signed JWT token for [testUserId] that the test verifier accepts. */
    private fun testToken(): String = JWT.create()
        .withSubject(testUserId.toString())
        .withAudience("authenticated")
        .sign(Algorithm.HMAC256(jwtSecret))

    /**
     * Builds a minimal Ktor test application that:
     *   - Installs a JWT provider backed by [jwtSecret]
     *   - Registers the userSearchRoutes with the supplied [service] and [dbReady]
     */
    private fun buildApp(
        service: UserSearchService = UserSearchService(),
        dbReady: Boolean = true,
        block: suspend io.ktor.server.testing.ApplicationTestBuilder.() -> Unit,
    ) = testApplication {
        application {
            configureSerialization()
            configureStatusPages()

            install(Authentication) {
                jwt(JWT_AUTH) {
                    verifier(
                        JWT.require(Algorithm.HMAC256(jwtSecret))
                            .withAudience("authenticated")
                            .build()
                    )
                    validate { credential ->
                        val sub = credential.payload.subject
                        if (sub != null) JWTPrincipal(credential.payload) else null
                    }
                }
            }

            routing {
                userSearchRoutes(service, databaseReady = dbReady)
            }
        }
        block()
    }

    // -----------------------------------------------------------------------
    // 400 Bad Request -- missing / invalid query parameter
    // -----------------------------------------------------------------------

    @Test
    fun `missing q parameter returns 400`() = buildApp {
        val response = client.get("/v1/users/search") {
            header(HttpHeaders.Authorization, "Bearer ${testToken()}")
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
        val body = response.bodyAsText()
        assertTrue(body.contains("bad_request"), "Expected error='bad_request' in: $body")
    }

    @Test
    fun `blank q parameter returns 400`() = buildApp {
        val response = client.get("/v1/users/search?q=") {
            header(HttpHeaders.Authorization, "Bearer ${testToken()}")
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
        val body = response.bodyAsText()
        assertTrue(body.contains("bad_request"), "Expected error='bad_request' in: $body")
    }

    @Test
    fun `single character q returns 400`() = buildApp {
        val response = client.get("/v1/users/search?q=a") {
            header(HttpHeaders.Authorization, "Bearer ${testToken()}")
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
        val body = response.bodyAsText()
        assertTrue(body.contains("bad_request"), "Expected error='bad_request' in: $body")
        assertTrue(
            body.contains("${UserSearchService.MIN_QUERY_LENGTH}"),
            "Expected min-length hint in: $body",
        )
    }

    // -----------------------------------------------------------------------
    // 503 Service Unavailable -- database not ready
    // -----------------------------------------------------------------------

    @Test
    fun `valid query with database not ready returns 503`() = buildApp(dbReady = false) {
        val response = client.get("/v1/users/search?q=john") {
            header(HttpHeaders.Authorization, "Bearer ${testToken()}")
        }
        assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
        val body = response.bodyAsText()
        assertTrue(body.contains("service_unavailable"), "Expected error='service_unavailable' in: $body")
    }

    // -----------------------------------------------------------------------
    // 200 OK -- successful search
    // -----------------------------------------------------------------------

    @Test
    fun `valid query returns 200 with search results`() {
        val stubService = object : UserSearchService() {
            override suspend fun search(query: String, callerId: UUID): UserSearchResponse {
                return UserSearchResponse(
                    results = listOf(
                        UserSearchResult(
                            id               = "00000000-0000-0000-0000-000000000002",
                            username         = "jane_doe",
                            displayName      = "Jane Doe",
                            avatarUrl        = null,
                            friendshipStatus = FriendshipStatusResponse.none,
                        ),
                    ),
                    total = 1,
                )
            }
        }

        buildApp(service = stubService) {
            val response = client.get("/v1/users/search?q=jane") {
                header(HttpHeaders.Authorization, "Bearer ${testToken()}")
            }
            assertEquals(HttpStatusCode.OK, response.status)

            val body = response.bodyAsText()
            val parsed = Json.decodeFromString<UserSearchResponse>(body)

            assertEquals(1, parsed.total)
            assertEquals(1, parsed.results.size)

            val result = parsed.results.first()
            assertEquals("jane_doe", result.username)
            assertEquals("Jane Doe", result.displayName)
            assertEquals(FriendshipStatusResponse.none, result.friendshipStatus)
        }
    }

    @Test
    fun `search result with friend and pending status is serialised correctly`() {
        val stubService = object : UserSearchService() {
            override suspend fun search(query: String, callerId: UUID): UserSearchResponse {
                return UserSearchResponse(
                    results = listOf(
                        UserSearchResult(
                            id               = "00000000-0000-0000-0000-000000000003",
                            username         = "bob",
                            displayName      = "Bob",
                            avatarUrl        = "https://example.com/bob.png",
                            friendshipStatus = FriendshipStatusResponse.friend,
                        ),
                        UserSearchResult(
                            id               = "00000000-0000-0000-0000-000000000004",
                            username         = "alice",
                            displayName      = "Alice",
                            avatarUrl        = null,
                            friendshipStatus = FriendshipStatusResponse.pending,
                        ),
                    ),
                    total = 2,
                )
            }
        }

        buildApp(service = stubService) {
            val response = client.get("/v1/users/search?q=bo") {
                header(HttpHeaders.Authorization, "Bearer ${testToken()}")
            }
            assertEquals(HttpStatusCode.OK, response.status)

            val parsed = Json.decodeFromString<UserSearchResponse>(response.bodyAsText())
            assertEquals(2, parsed.total)

            val bob = parsed.results.find { it.username == "bob" }
            assertNotNull(bob)
            assertEquals(FriendshipStatusResponse.friend, bob.friendshipStatus)
            assertEquals("https://example.com/bob.png", bob.avatarUrl)

            val alice = parsed.results.find { it.username == "alice" }
            assertNotNull(alice)
            assertEquals(FriendshipStatusResponse.pending, alice.friendshipStatus)
        }
    }

    @Test
    fun `empty result list returns 200 with empty results`() {
        val stubService = object : UserSearchService() {
            override suspend fun search(query: String, callerId: UUID): UserSearchResponse {
                return UserSearchResponse(results = emptyList(), total = 0)
            }
        }

        buildApp(service = stubService) {
            val response = client.get("/v1/users/search?q=zzz") {
                header(HttpHeaders.Authorization, "Bearer ${testToken()}")
            }
            assertEquals(HttpStatusCode.OK, response.status)

            val parsed = Json.decodeFromString<UserSearchResponse>(response.bodyAsText())
            assertEquals(0, parsed.total)
            assertTrue(parsed.results.isEmpty())
        }
    }

    // -----------------------------------------------------------------------
    // Service-layer constants
    // -----------------------------------------------------------------------

    @Test
    fun `UserSearchService MIN_QUERY_LENGTH is 2`() {
        assertEquals(2, UserSearchService.MIN_QUERY_LENGTH)
    }

    @Test
    fun `UserSearchService MAX_RESULTS is 20`() {
        assertEquals(20, UserSearchService.MAX_RESULTS)
    }
}
