package com.pushup.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.pushup.data.api.ApiException
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.CreateJoggingSessionRequest
import com.pushup.data.api.dto.CreateJoggingPlaybackEntryRequest
import com.pushup.data.api.dto.CreateRoutePointRequest
import com.pushup.data.api.dto.CreateWorkoutSessionRequest
import com.pushup.data.api.dto.LiveJoggingStatusDTO
import com.pushup.data.api.dto.SetUsernameRequest
import com.pushup.data.api.dto.UpdateJoggingSessionRequest
import com.pushup.data.api.dto.UpdateTimeCreditRequest
import com.pushup.data.api.dto.UpdateUserProfileRequest
import com.pushup.data.api.dto.UpdateWorkoutSessionRequest
import com.pushup.data.api.dto.UpsertLiveJoggingStatusRequest
import com.pushup.data.api.dto.UpsertUserLevelRequest
import com.pushup.data.api.dto.UsernameCheckResponse
import com.pushup.data.api.dto.UserProfileDTO
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.JoggingPlaybackEntry
import com.pushup.domain.model.LevelCalculator
import com.pushup.domain.model.RoutePoint
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.model.UserLevel
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.usecase.sync.AlwaysConnectedNetworkMonitor
import com.pushup.domain.usecase.sync.AlwaysOfflineNetworkMonitor
import com.pushup.domain.usecase.sync.NetworkMonitor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// =============================================================================
// Top-level helpers (accessible from nested classes)
// =============================================================================

private fun makeTestSession(
    id: String = "session-1",
    userId: String = "user-1",
    startedAt: Instant = Instant.fromEpochMilliseconds(1_700_000_000_000L),
    endedAt: Instant? = Instant.fromEpochMilliseconds(1_700_000_300_000L),
    pushUpCount: Int = 25,
    earnedTimeCreditSeconds: Long = 150L,
    quality: Float = 0.85f,
    syncStatus: SyncStatus = SyncStatus.PENDING,
) = WorkoutSession(id, userId, startedAt, endedAt, pushUpCount, earnedTimeCreditSeconds, quality, syncStatus)

private fun makeTestCredit(
    userId: String = "user-1",
    totalEarnedSeconds: Long = 3600L,
    totalSpentSeconds: Long = 1800L,
    lastUpdatedAt: Instant = Instant.fromEpochMilliseconds(1_700_000_000_000L),
    syncStatus: SyncStatus = SyncStatus.PENDING,
) = TimeCredit(
    userId = userId,
    totalEarnedSeconds = totalEarnedSeconds,
    totalSpentSeconds = totalSpentSeconds,
    dailyEarnedSeconds = (totalEarnedSeconds - totalSpentSeconds).coerceAtLeast(0L),
    dailySpentSeconds = 0L,
    lastResetAt = null,
    lastUpdatedAt = lastUpdatedAt,
    syncStatus = syncStatus,
)

/**
 * Tests for the cloud-sync extensions of [WorkoutSessionRepositoryImpl],
 * [TimeCreditRepositoryImpl], and [StatsRepositoryImpl].
 *
 * Each test uses an in-memory SQLite database and a fake [CloudSyncApi] /
 * [KtorApiClient] to verify online and offline behaviour without a real network.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class CloudSyncRepositoryTests {

    private lateinit var database: PushUpDatabase
    private val testDispatcher = StandardTestDispatcher()

    /** Fixed clock for deterministic timestamps. */
    private val fixedClock = object : Clock {
        var nowMs: Long = 1_700_000_000_000L
        override fun now(): Instant = Instant.fromEpochMilliseconds(nowMs)
    }

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        PushUpDatabase.Schema.create(driver)
        driver.execute(null, "PRAGMA foreign_keys = ON;", 0)
        database = PushUpDatabase(driver)
        // Insert a test user so FK constraints are satisfied.
        database.databaseQueries.insertUser(
            id = "user-1",
            email = "test@example.com",
            username = null,
            displayName = "Test User",
            avatarUrl = null,
            avatarVisibility = "everyone",
            createdAt = 1_700_000_000_000L,
            syncedAt = 1_700_000_000_000L,
        )
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // =========================================================================
    // Helpers (delegate to top-level functions)
    // =========================================================================

    private fun testSession(
        id: String = "session-1",
        userId: String = "user-1",
        startedAt: Instant = Instant.fromEpochMilliseconds(1_700_000_000_000L),
        endedAt: Instant? = Instant.fromEpochMilliseconds(1_700_000_300_000L),
        pushUpCount: Int = 25,
        earnedTimeCreditSeconds: Long = 150L,
        quality: Float = 0.85f,
        syncStatus: SyncStatus = SyncStatus.PENDING,
    ) = makeTestSession(id, userId, startedAt, endedAt, pushUpCount, earnedTimeCreditSeconds, quality, syncStatus)

    private fun testCredit(
        userId: String = "user-1",
        totalEarnedSeconds: Long = 3600L,
        totalSpentSeconds: Long = 1800L,
        lastUpdatedAt: Instant = Instant.fromEpochMilliseconds(1_700_000_000_000L),
        syncStatus: SyncStatus = SyncStatus.PENDING,
    ) = makeTestCredit(userId, totalEarnedSeconds, totalSpentSeconds, lastUpdatedAt, syncStatus)

    // =========================================================================
    // Fake CloudSyncApi
    // =========================================================================

    /**
     * Configurable fake [CloudSyncApi] for testing.
     *
     * Tracks calls and allows injection of responses or exceptions.
     */
    private class FakeCloudSyncApi : CloudSyncApi {
        var createSessionResponse: WorkoutSession? = null
        var createSessionException: Exception? = null
        var updateSessionResponse: WorkoutSession? = null
        var updateSessionException: Exception? = null
        var getSessionsResponse: List<WorkoutSession> = emptyList()
        var getSessionsException: Exception? = null
        var getSessionResponse: WorkoutSession? = null
        var getSessionException: Exception? = null
        var getTimeCreditResponse: TimeCredit? = null
        var updateTimeCreditResponse: TimeCredit? = null
        var updateTimeCreditException: Exception? = null

        val createSessionCalls = mutableListOf<CreateWorkoutSessionRequest>()
        val updateSessionCalls = mutableListOf<Pair<String, UpdateWorkoutSessionRequest>>()
        val updateTimeCreditCalls = mutableListOf<Pair<String, UpdateTimeCreditRequest>>()
        var getSessionsCalled = false
        var getTimeCreditCalled = false

        override suspend fun getWorkoutSessions(): List<WorkoutSession> {
            getSessionsCalled = true
            getSessionsException?.let { throw it }
            return getSessionsResponse
        }

        override suspend fun getWorkoutSession(id: String): WorkoutSession {
            getSessionException?.let { throw it }
            return getSessionResponse
                ?: throw ApiException.NotFound("Not found", "WorkoutSession", id)
        }

        override suspend fun createWorkoutSession(request: CreateWorkoutSessionRequest): WorkoutSession {
            createSessionCalls.add(request)
            createSessionException?.let { throw it }
            return createSessionResponse ?: makeTestSession(id = request.userId + "-created")
        }

        override suspend fun updateWorkoutSession(
            id: String,
            request: UpdateWorkoutSessionRequest,
        ): WorkoutSession {
            updateSessionCalls.add(id to request)
            updateSessionException?.let { throw it }
            return updateSessionResponse ?: makeTestSession(id = id)
        }

        override suspend fun getTimeCredit(userId: String): TimeCredit? {
            getTimeCreditCalled = true
            return getTimeCreditResponse
        }

        override suspend fun updateTimeCredit(
            userId: String,
            request: UpdateTimeCreditRequest,
        ): TimeCredit {
            updateTimeCreditCalls.add(userId to request)
            updateTimeCreditException?.let { throw it }
            return updateTimeCreditResponse ?: makeTestCredit(userId = userId)
        }

        override suspend fun getUserProfile(userId: String): UserProfileDTO? = null

        override suspend fun updateUserProfile(
            userId: String,
            request: UpdateUserProfileRequest,
        ): UserProfileDTO = UserProfileDTO(id = userId, displayName = null, email = null, updatedAt = null)

        override suspend fun getUserLevel(userId: String): UserLevel? = null

        override suspend fun upsertUserLevel(
            userId: String,
            request: UpsertUserLevelRequest,
        ): UserLevel = LevelCalculator.fromTotalXp(userId = userId, totalXp = request.totalXp)

        override suspend fun checkUsernameAvailability(username: String): UsernameCheckResponse =
            UsernameCheckResponse(username = username, available = true)

        override suspend fun setUsername(request: SetUsernameRequest): String = request.username

        // Jogging session stubs (not exercised by cloud-sync-repo tests)
        override suspend fun getJoggingSessions(): List<JoggingSession> = emptyList()
        override suspend fun getJoggingSession(id: String): JoggingSession =
            throw ApiException.NotFound("Not found", "JoggingSession", id)
        override suspend fun createJoggingSession(request: CreateJoggingSessionRequest): JoggingSession =
            throw UnsupportedOperationException()
        override suspend fun updateJoggingSession(id: String, request: UpdateJoggingSessionRequest): JoggingSession =
            throw UnsupportedOperationException()
        override suspend fun getRoutePoints(sessionId: String): List<RoutePoint> = emptyList()
        override suspend fun createRoutePoints(requests: List<CreateRoutePointRequest>): List<RoutePoint> = emptyList()
        override suspend fun getJoggingPlaybackEntries(sessionId: String): List<JoggingPlaybackEntry> = emptyList()
        override suspend fun replaceJoggingPlaybackEntries(
            sessionId: String,
            requests: List<CreateJoggingPlaybackEntryRequest>,
        ) {}
        override suspend fun upsertLiveJoggingStatus(request: UpsertLiveJoggingStatusRequest) {}
        override suspend fun deleteLiveJoggingStatus(userId: String) {}
        override suspend fun getLiveJoggingStatuses(userIds: List<String>): List<LiveJoggingStatusDTO> = emptyList()
    }

    // =========================================================================
    // Fake KtorApiClient -- we cannot instantiate the real one without a server
    // =========================================================================

    /**
     * Configurable fake stats source that mimics [KtorApiClient] responses.
     *
     * Since [KtorApiClient] is a concrete class backed by a real HTTP client,
     * we test the fallback behaviour by injecting a [NetworkMonitor] that
     * reports offline, which forces [StatsRepositoryImpl] to use local data.
     *
     * For the "API available" path we verify that the repository delegates to
     * the API by checking that local data is NOT consulted when the API succeeds.
     * We achieve this by using a subclass of [StatsRepositoryImpl] that overrides
     * the local computation path -- but since the class is not open, we instead
     * test the observable behaviour: when offline, local data is returned; when
     * online and the API is unavailable (no real server), the fallback kicks in.
     */

    // =========================================================================
    // WorkoutSessionRepositoryImpl -- Online Scenarios
    // =========================================================================

    @Test
    fun sessionRepo_save_localPersistenceIsImmediateRegardlessOfNetwork() = runTest {
        val fakeApi = FakeCloudSyncApi()
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )
        val session = testSession()

        repo.save(session)

        // Local persistence must be immediate -- no need to advance coroutines.
        val local = repo.getById(session.id)
        assertNotNull(local)
        assertEquals(session.id, local.id)
    }

    @Test
    fun sessionRepo_save_preservesSyncedStatus_noUploadTriggered() = runTest {
        val fakeApi = FakeCloudSyncApi()
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )
        // Session with SYNCED status should be saved as-is (already on server).
        val syncedSession = testSession(syncStatus = SyncStatus.SYNCED)
        repo.save(syncedSession)
        advanceUntilIdle()

        val local = repo.getById(syncedSession.id)
        assertNotNull(local)
        assertEquals(SyncStatus.SYNCED, local.syncStatus)
        // No background upload should be triggered for SYNCED sessions.
        assertTrue(fakeApi.createSessionCalls.isEmpty())
    }

    @Test
    fun sessionRepo_save_pendingSession_triggersBackgroundUpload() = runTest {
        val fakeApi = FakeCloudSyncApi()
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )
        val session = testSession(syncStatus = SyncStatus.PENDING)

        repo.save(session)
        advanceUntilIdle() // Let background coroutines complete.

        // The background sync should have called createWorkoutSession with the correct session ID.
        assertEquals(1, fakeApi.createSessionCalls.size)
        assertEquals(session.userId, fakeApi.createSessionCalls.first().userId)
        assertEquals(session.startedAt.toString(), fakeApi.createSessionCalls.first().startedAt)
    }

    @Test
    fun sessionRepo_save_backgroundSync_marksLocalAsSyncedOnSuccess() = runTest {
        val fakeApi = FakeCloudSyncApi()
        fakeApi.createSessionResponse = testSession(syncStatus = SyncStatus.SYNCED)
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )
        val session = testSession(syncStatus = SyncStatus.PENDING)

        repo.save(session)
        advanceUntilIdle()

        val local = repo.getById(session.id)
        assertNotNull(local)
        assertEquals(SyncStatus.SYNCED, local.syncStatus)
    }

    @Test
    fun sessionRepo_save_backgroundSync_fallsBackToUpdateOnConflict() = runTest {
        val fakeApi = FakeCloudSyncApi()
        // createWorkoutSession throws a generic exception (simulating 409 Conflict).
        fakeApi.createSessionException = RuntimeException("Conflict")
        fakeApi.updateSessionResponse = testSession(syncStatus = SyncStatus.SYNCED)
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )
        val session = testSession(syncStatus = SyncStatus.PENDING)

        repo.save(session)
        advanceUntilIdle()

        // Should have fallen back to updateWorkoutSession.
        assertEquals(1, fakeApi.updateSessionCalls.size)
        assertEquals(session.id, fakeApi.updateSessionCalls.first().first)
    }

    @Test
    fun sessionRepo_save_backgroundSync_skippedWhenOffline() = runTest {
        val fakeApi = FakeCloudSyncApi()
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysOfflineNetworkMonitor,
            syncScope = this,
        )
        val session = testSession(syncStatus = SyncStatus.PENDING)

        repo.save(session)
        advanceUntilIdle()

        // No API calls should have been made when offline.
        assertTrue(fakeApi.createSessionCalls.isEmpty())
        assertTrue(fakeApi.updateSessionCalls.isEmpty())
    }

    @Test
    fun sessionRepo_save_backgroundSync_skippedWhenNoApiConfigured() = runTest {
        // No cloudSyncApi provided -- local-only mode.
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            syncScope = this,
        )
        val session = testSession(syncStatus = SyncStatus.PENDING)

        repo.save(session)
        advanceUntilIdle()

        // Session is saved locally with PENDING status.
        val local = repo.getById(session.id)
        assertNotNull(local)
        assertEquals(SyncStatus.PENDING, local.syncStatus)
    }

    @Test
    fun sessionRepo_save_backgroundSync_silentlySwallowsApiFailure() = runTest {
        val fakeApi = FakeCloudSyncApi()
        fakeApi.createSessionException = RuntimeException("Network error")
        fakeApi.updateSessionException = RuntimeException("Network error")
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )
        val session = testSession(syncStatus = SyncStatus.PENDING)

        // Should not throw even when both create and update fail.
        repo.save(session)
        advanceUntilIdle()

        // Session remains locally with PENDING status.
        val local = repo.getById(session.id)
        assertNotNull(local)
        assertEquals(SyncStatus.PENDING, local.syncStatus)
    }

    // =========================================================================
    // WorkoutSessionRepositoryImpl -- getAllByUserId cloud merge
    // =========================================================================

    @Test
    fun sessionRepo_getAllByUserId_returnsLocalDataImmediately() = runTest {
        val fakeApi = FakeCloudSyncApi()
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )
        repo.save(testSession(id = "s1", syncStatus = SyncStatus.SYNCED))
        repo.save(testSession(id = "s2", syncStatus = SyncStatus.SYNCED))

        val result = repo.getAllByUserId("user-1")

        assertEquals(2, result.size)
    }

    @Test
    fun sessionRepo_getAllByUserId_triggersBackgroundCloudMerge_online() = runTest {
        val remoteSession = testSession(
            id = "remote-session",
            syncStatus = SyncStatus.SYNCED,
        )
        val fakeApi = FakeCloudSyncApi()
        fakeApi.getSessionsResponse = listOf(remoteSession)
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )

        repo.getAllByUserId("user-1")
        advanceUntilIdle() // Let background merge complete.

        // The remote session should now be in the local DB.
        assertTrue(fakeApi.getSessionsCalled)
        val merged = repo.getById("remote-session")
        assertNotNull(merged)
        assertEquals(SyncStatus.SYNCED, merged.syncStatus)
    }

    @Test
    fun sessionRepo_getAllByUserId_noBackgroundMerge_whenOffline() = runTest {
        val fakeApi = FakeCloudSyncApi()
        fakeApi.getSessionsResponse = listOf(testSession(id = "remote-session"))
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysOfflineNetworkMonitor,
            syncScope = this,
        )

        repo.getAllByUserId("user-1")
        advanceUntilIdle()

        // No API calls when offline.
        assertTrue(!fakeApi.getSessionsCalled)
        assertNull(repo.getById("remote-session"))
    }

    @Test
    fun sessionRepo_cloudMerge_keepsLocalWhenLocalIsNewer() = runTest {
        val localStartedAt = Instant.fromEpochMilliseconds(1_700_000_200_000L)
        val remoteStartedAt = Instant.fromEpochMilliseconds(1_700_000_100_000L) // older

        val localSession = testSession(
            id = "session-conflict",
            startedAt = localStartedAt,
            syncStatus = SyncStatus.PENDING,
        )
        val remoteSession = testSession(
            id = "session-conflict",
            startedAt = remoteStartedAt,
            pushUpCount = 999, // different data to verify which one wins
            syncStatus = SyncStatus.SYNCED,
        )

        val fakeApi = FakeCloudSyncApi()
        fakeApi.getSessionsResponse = listOf(remoteSession)
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )

        // Save local session first.
        repo.save(localSession)
        advanceUntilIdle() // Let background sync from save() complete.

        // Reset call tracking.
        fakeApi.createSessionCalls.clear()
        fakeApi.updateSessionCalls.clear()

        repo.getAllByUserId("user-1")
        advanceUntilIdle()

        // Local session should be kept (local is newer).
        val result = repo.getById("session-conflict")
        assertNotNull(result)
        // pushUpCount should be from the local session (25), not the remote (999).
        assertEquals(25, result.pushUpCount)
    }

    @Test
    fun sessionRepo_cloudMerge_overwritesLocalWhenRemoteIsNewer() = runTest {
        val localStartedAt = Instant.fromEpochMilliseconds(1_700_000_100_000L)
        val remoteStartedAt = Instant.fromEpochMilliseconds(1_700_000_200_000L) // newer

        val localSession = testSession(
            id = "session-conflict",
            startedAt = localStartedAt,
            pushUpCount = 10,
            syncStatus = SyncStatus.SYNCED,
        )
        val remoteSession = testSession(
            id = "session-conflict",
            startedAt = remoteStartedAt,
            pushUpCount = 50, // remote has more push-ups
            syncStatus = SyncStatus.SYNCED,
        )

        val fakeApi = FakeCloudSyncApi()
        fakeApi.getSessionsResponse = listOf(remoteSession)
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )

        // Save local session first (as SYNCED to avoid background upload).
        repo.save(localSession)
        advanceUntilIdle()

        repo.getAllByUserId("user-1")
        advanceUntilIdle()

        // Remote session should overwrite local (remote is newer).
        val result = repo.getById("session-conflict")
        assertNotNull(result)
        assertEquals(50, result.pushUpCount)
        assertEquals(SyncStatus.SYNCED, result.syncStatus)
    }

    // =========================================================================
    // TimeCreditRepositoryImpl -- Cloud Sync
    // =========================================================================

    @Test
    fun creditRepo_addEarnedSeconds_triggersBackgroundSync_online() = runTest {
        val fakeApi = FakeCloudSyncApi()
        val repo = TimeCreditRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )

        repo.addEarnedSeconds("user-1", 300L)
        advanceUntilIdle()

        // Background sync should have called updateTimeCredit.
        assertEquals(1, fakeApi.updateTimeCreditCalls.size)
        val (userId, request) = fakeApi.updateTimeCreditCalls.first()
        assertEquals("user-1", userId)
        assertEquals(300L, request.totalEarnedSeconds)
        assertEquals(0L, request.totalSpentSeconds)
    }

    @Test
    fun creditRepo_addSpentSeconds_triggersBackgroundSync_online() = runTest {
        val fakeApi = FakeCloudSyncApi()
        val repo = TimeCreditRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )
        // First add some earned credits.
        repo.addEarnedSeconds("user-1", 600L)
        advanceUntilIdle()
        fakeApi.updateTimeCreditCalls.clear()

        repo.addSpentSeconds("user-1", 200L)
        advanceUntilIdle()

        assertEquals(1, fakeApi.updateTimeCreditCalls.size)
        val (userId, request) = fakeApi.updateTimeCreditCalls.first()
        assertEquals("user-1", userId)
        assertEquals(600L, request.totalEarnedSeconds)
        assertEquals(200L, request.totalSpentSeconds)
    }

    @Test
    fun creditRepo_addEarnedSeconds_noSync_whenOffline() = runTest {
        val fakeApi = FakeCloudSyncApi()
        val repo = TimeCreditRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysOfflineNetworkMonitor,
            syncScope = this,
        )

        repo.addEarnedSeconds("user-1", 300L)
        advanceUntilIdle()

        // No API calls when offline.
        assertTrue(fakeApi.updateTimeCreditCalls.isEmpty())

        // Local record should still be updated.
        val local = repo.get("user-1")
        assertNotNull(local)
        assertEquals(300L, local.totalEarnedSeconds)
        assertEquals(SyncStatus.PENDING, local.syncStatus)
    }

    @Test
    fun creditRepo_addEarnedSeconds_marksLocalAsSyncedAfterSuccessfulSync() = runTest {
        val fakeApi = FakeCloudSyncApi()
        val repo = TimeCreditRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )

        repo.addEarnedSeconds("user-1", 300L)
        advanceUntilIdle()

        val local = repo.get("user-1")
        assertNotNull(local)
        assertEquals(SyncStatus.SYNCED, local.syncStatus)
    }

    @Test
    fun creditRepo_addEarnedSeconds_remainsPendingAfterSyncFailure() = runTest {
        val fakeApi = FakeCloudSyncApi()
        fakeApi.updateTimeCreditException = RuntimeException("Network error")
        val repo = TimeCreditRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )

        repo.addEarnedSeconds("user-1", 300L)
        advanceUntilIdle()

        // Should remain PENDING after sync failure.
        val local = repo.get("user-1")
        assertNotNull(local)
        assertEquals(SyncStatus.PENDING, local.syncStatus)
    }

    @Test
    fun creditRepo_update_withSyncedStatus_doesNotTriggerBackgroundSync() = runTest {
        val fakeApi = FakeCloudSyncApi()
        val repo = TimeCreditRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )
        // Simulate a pull from cloud -- status is SYNCED.
        val cloudCredit = testCredit(syncStatus = SyncStatus.SYNCED)

        repo.update(cloudCredit)
        advanceUntilIdle()

        // No background sync should be triggered for SYNCED records.
        assertTrue(fakeApi.updateTimeCreditCalls.isEmpty())
    }

    @Test
    fun creditRepo_update_withPendingStatus_triggersBackgroundSync() = runTest {
        val fakeApi = FakeCloudSyncApi()
        val repo = TimeCreditRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )
        val pendingCredit = testCredit(syncStatus = SyncStatus.PENDING)

        repo.update(pendingCredit)
        advanceUntilIdle()

        assertEquals(1, fakeApi.updateTimeCreditCalls.size)
    }

    @Test
    fun creditRepo_noApiConfigured_localOnlyBehaviour() = runTest {
        // No cloudSyncApi -- local-only mode.
        val repo = TimeCreditRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            syncScope = this,
        )

        repo.addEarnedSeconds("user-1", 500L)
        advanceUntilIdle()

        val local = repo.get("user-1")
        assertNotNull(local)
        assertEquals(500L, local.totalEarnedSeconds)
        assertEquals(SyncStatus.PENDING, local.syncStatus)
    }

    // =========================================================================
    // StatsRepositoryImpl -- Local fallback when offline
    // =========================================================================

    private fun createStatsRepo(
        networkMonitor: NetworkMonitor = AlwaysOfflineNetworkMonitor,
    ): StatsRepositoryImpl {
        val timeCreditRepo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)
        return StatsRepositoryImpl(
            database = database,
            timeCreditRepository = timeCreditRepo,
            dispatcher = testDispatcher,
            timeZone = TimeZone.UTC,
            clock = fixedClock,
            // No KtorApiClient -- tests the local fallback path.
            ktorApiClient = null,
            networkMonitor = networkMonitor,
        )
    }

    private fun insertSession(
        id: String,
        startedAtMs: Long,
        endedAtMs: Long,
        pushUpCount: Int,
        earnedSeconds: Long,
        quality: Float,
    ) {
        database.databaseQueries.insertWorkoutSession(
            id = id,
            userId = "user-1",
            startedAt = startedAtMs,
            endedAt = endedAtMs,
            pushUpCount = pushUpCount.toLong(),
            earnedTimeCredits = earnedSeconds,
            quality = quality.toDouble(),
            syncStatus = "synced",
            updatedAt = startedAtMs,
        )
    }

    @Test
    fun statsRepo_getDailyStats_usesLocalWhenOffline() = runTest {
        val repo = createStatsRepo(AlwaysOfflineNetworkMonitor)

        // 2023-11-15T00:00:00Z = 1700006400000
        val dayStart = 1_700_006_400_000L
        insertSession(
            id = "s1",
            startedAtMs = dayStart + 3_600_000,
            endedAtMs = dayStart + 3_900_000,
            pushUpCount = 20,
            earnedSeconds = 120L,
            quality = 0.8f,
        )

        val result = repo.getDailyStats("user-1", LocalDate(2023, 11, 15))

        assertNotNull(result)
        assertEquals(20, result.totalPushUps)
        assertEquals(1, result.totalSessions)
    }

    @Test
    fun statsRepo_getDailyStats_returnsNullForEmptyDayWhenOffline() = runTest {
        val repo = createStatsRepo(AlwaysOfflineNetworkMonitor)

        val result = repo.getDailyStats("user-1", LocalDate(2023, 11, 15))

        assertNull(result)
    }

    @Test
    fun statsRepo_getWeeklyStats_usesLocalWhenOffline() = runTest {
        val repo = createStatsRepo(AlwaysOfflineNetworkMonitor)

        // Week of 2023-11-13 (Monday)
        val mondayStart = 1_699_833_600_000L
        insertSession(
            id = "s1",
            startedAtMs = mondayStart + 3_600_000,
            endedAtMs = mondayStart + 3_900_000,
            pushUpCount = 30,
            earnedSeconds = 180L,
            quality = 0.9f,
        )

        val result = repo.getWeeklyStats("user-1", LocalDate(2023, 11, 13))

        assertNotNull(result)
        assertEquals(30, result.totalPushUps)
        assertEquals(7, result.dailyBreakdown.size)
    }

    @Test
    fun statsRepo_getMonthlyStats_usesLocalWhenOffline() = runTest {
        val repo = createStatsRepo(AlwaysOfflineNetworkMonitor)

        // Nov 1, 2023 = 1698796800000
        val nov1 = 1_698_796_800_000L
        insertSession(
            id = "s1",
            startedAtMs = nov1 + 3_600_000,
            endedAtMs = nov1 + 3_900_000,
            pushUpCount = 25,
            earnedSeconds = 150L,
            quality = 0.85f,
        )

        val result = repo.getMonthlyStats("user-1", 11, 2023)

        assertNotNull(result)
        assertEquals(25, result.totalPushUps)
        assertEquals(11, result.month)
        assertEquals(2023, result.year)
    }

    @Test
    fun statsRepo_getTotalStats_usesLocalWhenOffline() = runTest {
        val repo = createStatsRepo(AlwaysOfflineNetworkMonitor)

        val dayStart = 1_700_006_400_000L
        insertSession(
            id = "s1",
            startedAtMs = dayStart + 3_600_000,
            endedAtMs = dayStart + 3_900_000,
            pushUpCount = 40,
            earnedSeconds = 240L,
            quality = 0.9f,
        )

        fixedClock.nowMs = dayStart + 3_600_000
        val result = repo.getTotalStats("user-1")

        assertNotNull(result)
        assertEquals(40, result.totalPushUps)
        assertEquals(1, result.totalSessions)
    }

    @Test
    fun statsRepo_getDailyStats_fallsBackToLocalWhenApiUnavailable() = runTest {
        // No KtorApiClient configured -- always uses local.
        val repo = createStatsRepo(AlwaysConnectedNetworkMonitor)

        val dayStart = 1_700_006_400_000L
        insertSession(
            id = "s1",
            startedAtMs = dayStart + 3_600_000,
            endedAtMs = dayStart + 3_900_000,
            pushUpCount = 15,
            earnedSeconds = 90L,
            quality = 0.75f,
        )

        // Even when "online", no KtorApiClient means local computation is used.
        val result = repo.getDailyStats("user-1", LocalDate(2023, 11, 15))

        assertNotNull(result)
        assertEquals(15, result.totalPushUps)
    }

    @Test
    fun statsRepo_noApiConfigured_alwaysUsesLocal() = runTest {
        val timeCreditRepo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)
        val repo = StatsRepositoryImpl(
            database = database,
            timeCreditRepository = timeCreditRepo,
            dispatcher = testDispatcher,
            timeZone = TimeZone.UTC,
            clock = fixedClock,
            // Explicitly null -- local-only mode.
            ktorApiClient = null,
            networkMonitor = null,
        )

        val dayStart = 1_700_006_400_000L
        insertSession(
            id = "s1",
            startedAtMs = dayStart + 3_600_000,
            endedAtMs = dayStart + 3_900_000,
            pushUpCount = 10,
            earnedSeconds = 60L,
            quality = 0.7f,
        )

        val result = repo.getDailyStats("user-1", LocalDate(2023, 11, 15))

        assertNotNull(result)
        assertEquals(10, result.totalPushUps)
    }

    // =========================================================================
    // WorkoutSessionRepositoryImpl -- finishSession triggers background sync
    // =========================================================================

    @Test
    fun sessionRepo_finishSession_triggersBackgroundSync() = runTest {
        val fakeApi = FakeCloudSyncApi()
        val repo = WorkoutSessionRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = fakeApi,
            networkMonitor = AlwaysConnectedNetworkMonitor,
            syncScope = this,
        )
        // Save an active session first (as SYNCED to avoid initial upload).
        val activeSession = testSession(
            id = "active-session",
            endedAt = null,
            syncStatus = SyncStatus.SYNCED,
        )
        repo.save(activeSession)
        advanceUntilIdle()
        fakeApi.createSessionCalls.clear()
        fakeApi.updateSessionCalls.clear()

        // Finish the session.
        repo.finishSession(
            id = "active-session",
            endedAt = Instant.fromEpochMilliseconds(1_700_000_300_000L),
            earnedTimeCreditSeconds = 150L,
        )
        advanceUntilIdle()

        // Background sync should have been triggered for the finished session.
        // It will try create first (which may fail), then update.
        assertTrue(
            fakeApi.createSessionCalls.isNotEmpty() || fakeApi.updateSessionCalls.isNotEmpty(),
            "Expected at least one API call after finishSession",
        )
    }
}
