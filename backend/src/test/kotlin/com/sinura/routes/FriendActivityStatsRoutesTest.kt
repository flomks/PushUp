package com.sinura.routes

import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import com.sinura.dto.DateRangeDTO
import com.sinura.dto.FriendActivityStatsDTO
import com.sinura.dto.StatsPeriod
import com.sinura.plugins.JWT_AUTH
import com.sinura.plugins.configureSerialization
import com.sinura.plugins.configureStatusPages
import com.sinura.service.FriendActivityStatsResult
import com.sinura.service.FriendActivityStatsService
import io.ktor.client.request.bearerAuth
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.install
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.jwt.JWTPrincipal
import io.ktor.server.auth.jwt.jwt
import io.ktor.server.routing.routing
import io.ktor.server.testing.testApplication
import java.time.LocalDate
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals

/**
 * Integration-style tests for GET /v1/friends/{id}/stats.
 *
 * These tests use Ktor's [testApplication] engine with a stub
 * [FriendActivityStatsService] so that no real database connection is required.
 */
class FriendActivityStatsRoutesTest {

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
     * - [friendActivityStatsRoutes] wired with the supplied [service]
     */
    private fun withApp(
        service: FriendActivityStatsService,
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
                friendActivityStatsRoutes(service, databaseReady = databaseReady)
            }
        }
        val client = createClient { }
        client.block()
    }

    /** A stub service that always returns [FriendActivityStatsResult.NotFriends]. */
    private val notFriendsService = object : FriendActivityStatsService() {
        override suspend fun getStats(
            callerId: UUID,
            friendId: UUID,
            period: StatsPeriod,
            today: LocalDate,
        ): FriendActivityStatsResult = FriendActivityStatsResult.NotFriends
    }

    /** Builds a stub service that returns a successful [FriendActivityStatsDTO]. */
    private fun successService(
        friendId: UUID,
        period: StatsPeriod = StatsPeriod.week,
        pushupCount: Int = 42,
    ) = object : FriendActivityStatsService() {
        override suspend fun getStats(
            callerId: UUID,
            friendId: UUID,
            period: StatsPeriod,
            today: LocalDate,
        ): FriendActivityStatsResult = FriendActivityStatsResult.Success(
            FriendActivityStatsDTO(
                friendId           = friendId.toString(),
                period             = period.name,
                dateRange          = DateRangeDTO(from = "2026-03-02", to = "2026-03-08"),
                pushupCount        = pushupCount,
                activityPoints     = 128,
                totalSessions      = 5,
                totalEarnedSeconds = 252L,
                averageQuality     = 0.87,
            ),
        )
    }

    // -----------------------------------------------------------------------
    // Auth / infrastructure tests
    // -----------------------------------------------------------------------

    @Test
    fun `returns 401 when no token is provided`() = withApp(notFriendsService) {
        val response = get("/v1/friends/${UUID.randomUUID()}/stats?period=week")
        assertEquals(HttpStatusCode.Unauthorized, response.status)
    }

    @Test
    fun `returns 503 when database is not ready`() =
        withApp(notFriendsService, databaseReady = false) {
            val response = get("/v1/friends/${UUID.randomUUID()}/stats?period=week") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.ServiceUnavailable, response.status)
        }

    // -----------------------------------------------------------------------
    // Input validation tests
    // -----------------------------------------------------------------------

    @Test
    fun `returns 400 when id is not a valid UUID`() = withApp(notFriendsService) {
        val response = get("/v1/friends/not-a-uuid/stats?period=week") {
            bearerAuth(buildToken())
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
        assertContains(response.bodyAsText(), "bad_request")
    }

    @Test
    fun `returns 400 when period parameter is missing`() = withApp(notFriendsService) {
        val response = get("/v1/friends/${UUID.randomUUID()}/stats") {
            bearerAuth(buildToken())
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
        assertContains(response.bodyAsText(), "period")
    }

    @Test
    fun `returns 400 when period parameter is invalid`() = withApp(notFriendsService) {
        val response = get("/v1/friends/${UUID.randomUUID()}/stats?period=year") {
            bearerAuth(buildToken())
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
        assertContains(response.bodyAsText(), "bad_request")
    }

    // -----------------------------------------------------------------------
    // Friendship guard tests
    // -----------------------------------------------------------------------

    @Test
    fun `returns 403 when users are not friends`() = withApp(notFriendsService) {
        val response = get("/v1/friends/${UUID.randomUUID()}/stats?period=week") {
            bearerAuth(buildToken())
        }
        assertEquals(HttpStatusCode.Forbidden, response.status)
        assertContains(response.bodyAsText(), "forbidden")
    }

    @Test
    fun `returns 403 error body contains descriptive message`() = withApp(notFriendsService) {
        val response = get("/v1/friends/${UUID.randomUUID()}/stats?period=day") {
            bearerAuth(buildToken())
        }
        assertEquals(HttpStatusCode.Forbidden, response.status)
        val body = response.bodyAsText()
        assertContains(body, "not friends")
    }

    // -----------------------------------------------------------------------
    // Success path tests
    // -----------------------------------------------------------------------

    @Test
    fun `returns 200 with stats body for period=day`() {
        val friendId = UUID.randomUUID()
        withApp(successService(friendId, StatsPeriod.day, pushupCount = 10)) {
            val response = get("/v1/friends/$friendId/stats?period=day") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            assertContains(body, "\"pushupCount\"")
            assertContains(body, "\"period\"")
            assertContains(body, "\"dateRange\"")
            assertContains(body, "day")
        }
    }

    @Test
    fun `returns 200 with stats body for period=week`() {
        val friendId = UUID.randomUUID()
        withApp(successService(friendId, StatsPeriod.week, pushupCount = 42)) {
            val response = get("/v1/friends/$friendId/stats?period=week") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            assertContains(body, "\"pushupCount\"")
            assertContains(body, "\"period\"")
            assertContains(body, "\"dateRange\"")
            assertContains(body, "week")
            assertContains(body, "42")
        }
    }

    @Test
    fun `returns 200 with stats body for period=month`() {
        val friendId = UUID.randomUUID()
        withApp(successService(friendId, StatsPeriod.month, pushupCount = 200)) {
            val response = get("/v1/friends/$friendId/stats?period=month") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            assertContains(body, "\"pushupCount\"")
            assertContains(body, "month")
            assertContains(body, "200")
        }
    }

    @Test
    fun `response body contains all required fields`() {
        val friendId = UUID.randomUUID()
        withApp(successService(friendId)) {
            val response = get("/v1/friends/$friendId/stats?period=week") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            // Acceptance criteria: response must contain pushup_count, period, date_range
            assertContains(body, "\"pushupCount\"")
            assertContains(body, "\"period\"")
            assertContains(body, "\"dateRange\"")
            assertContains(body, "\"from\"")
            assertContains(body, "\"to\"")
            assertContains(body, "\"friendId\"")
            assertContains(body, "\"totalSessions\"")
            assertContains(body, "\"totalEarnedSeconds\"")
        }
    }

    @Test
    fun `response body contains the correct friendId`() {
        val friendId = UUID.randomUUID()
        withApp(successService(friendId)) {
            val response = get("/v1/friends/$friendId/stats?period=week") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
            assertContains(response.bodyAsText(), friendId.toString())
        }
    }

    @Test
    fun `period parameter is case-insensitive`() {
        val friendId = UUID.randomUUID()
        withApp(successService(friendId, StatsPeriod.week)) {
            val response = get("/v1/friends/$friendId/stats?period=WEEK") {
                bearerAuth(buildToken())
            }
            assertEquals(HttpStatusCode.OK, response.status)
        }
    }
}
