package com.pushup.domain.usecase.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.pushup.data.api.ApiException
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.CreateWorkoutSessionRequest
import com.pushup.data.api.dto.UpdateTimeCreditRequest
import com.pushup.data.api.dto.UpdateWorkoutSessionRequest
import com.pushup.data.repository.TimeCreditRepositoryImpl
import com.pushup.data.repository.UserRepositoryImpl
import com.pushup.data.repository.WorkoutSessionRepositoryImpl
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.AuthToken
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.model.User
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.AuthRepository
import com.pushup.domain.repository.TimeCreditRepository
import com.pushup.domain.repository.UserRepository
import com.pushup.domain.repository.WorkoutSessionRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Unit tests for the cloud-sync use-cases (Task 1B.9):
 * - [SyncWorkoutsUseCase]
 * - [SyncTimeCreditUseCase]
 * - [SyncFromCloudUseCase]
 * - [SyncManager]
 *
 * Uses an in-memory SQLite database for the local repositories and a
 * [FakeCloudSyncApi] for the remote API. A [FakeAuthRepository] provides
 * the current user without requiring a real Supabase connection.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SyncUseCaseTests {

    private val testDispatcher = StandardTestDispatcher()

    private val fixedClock = object : Clock {
        @Volatile var nowMs: Long = 1_700_000_000_000L
        override fun now(): Instant = Instant.fromEpochMilliseconds(nowMs)
    }

    private lateinit var database: PushUpDatabase
    private lateinit var userRepo: UserRepository
    private lateinit var sessionRepo: WorkoutSessionRepository
    private lateinit var timeCreditRepo: TimeCreditRepository
    private lateinit var fakeSupabase: FakeCloudSyncApi
    private lateinit var fakeAuthRepo: FakeAuthRepository

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)

        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        PushUpDatabase.Schema.create(driver)
        driver.execute(null, "PRAGMA foreign_keys = ON;", 0)
        database = PushUpDatabase(driver)

        userRepo = UserRepositoryImpl(database, testDispatcher)
        sessionRepo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)
        timeCreditRepo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)
        fakeSupabase = FakeCloudSyncApi()
        fakeAuthRepo = FakeAuthRepository()
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private val baseInstant = Instant.fromEpochMilliseconds(1_700_000_000_000L)

    private suspend fun insertUser(id: String = "user-1"): User {
        val user = User(
            id = id,
            email = "test@example.com",
            displayName = "Test User",
            createdAt = baseInstant,
            lastSyncedAt = baseInstant,
        )
        userRepo.saveUser(user)
        return user
    }

    private suspend fun insertPendingSession(
        id: String = "session-1",
        userId: String = "user-1",
        startedAt: Instant = baseInstant,
        endedAt: Instant? = baseInstant.plus(kotlin.time.Duration.parse("PT5M")),
        pushUpCount: Int = 10,
        earnedTimeCreditSeconds: Long = 60L,
        quality: Float = 0.8f,
    ): WorkoutSession {
        val session = WorkoutSession(
            id = id,
            userId = userId,
            startedAt = startedAt,
            endedAt = endedAt,
            pushUpCount = pushUpCount,
            earnedTimeCreditSeconds = earnedTimeCreditSeconds,
            quality = quality,
            syncStatus = SyncStatus.PENDING,
        )
        sessionRepo.save(session)
        return session
    }

    private suspend fun insertSyncedSession(
        id: String = "session-synced",
        userId: String = "user-1",
        startedAt: Instant = baseInstant,
    ): WorkoutSession {
        val session = WorkoutSession(
            id = id,
            userId = userId,
            startedAt = startedAt,
            endedAt = startedAt.plus(kotlin.time.Duration.parse("PT5M")),
            pushUpCount = 5,
            earnedTimeCreditSeconds = 30L,
            quality = 0.7f,
            syncStatus = SyncStatus.SYNCED,
        )
        sessionRepo.save(session)
        return session
    }

    private suspend fun insertPendingCredit(
        userId: String = "user-1",
        earned: Long = 300L,
        spent: Long = 100L,
        lastUpdatedAt: Instant = baseInstant,
    ): TimeCredit {
        val credit = TimeCredit(
            userId = userId,
            totalEarnedSeconds = earned,
            totalSpentSeconds = spent,
            lastUpdatedAt = lastUpdatedAt,
            syncStatus = SyncStatus.PENDING,
        )
        timeCreditRepo.update(credit)
        return credit
    }

    private fun makeSyncWorkoutsUseCase(
        networkMonitor: NetworkMonitor = AlwaysConnectedNetworkMonitor,
    ) = SyncWorkoutsUseCase(
        sessionRepository = sessionRepo,
        supabaseClient = fakeSupabase,
        networkMonitor = networkMonitor,
        maxRetries = 2,
        baseDelayMs = 0L, // No delay in tests
    )

    private fun makeSyncTimeCreditUseCase(
        networkMonitor: NetworkMonitor = AlwaysConnectedNetworkMonitor,
    ) = SyncTimeCreditUseCase(
        timeCreditRepository = timeCreditRepo,
        supabaseClient = fakeSupabase,
        networkMonitor = networkMonitor,
        maxRetries = 2,
        baseDelayMs = 0L,
    )

    private fun makeSyncFromCloudUseCase(
        networkMonitor: NetworkMonitor = AlwaysConnectedNetworkMonitor,
    ) = SyncFromCloudUseCase(
        sessionRepository = sessionRepo,
        timeCreditRepository = timeCreditRepo,
        supabaseClient = fakeSupabase,
        networkMonitor = networkMonitor,
        maxRetries = 2,
        baseDelayMs = 0L,
    )

    private fun makeSyncManager(
        networkMonitor: NetworkMonitor = AlwaysConnectedNetworkMonitor,
    ) = SyncManager(
        syncWorkoutsUseCase = makeSyncWorkoutsUseCase(networkMonitor),
        syncTimeCreditUseCase = makeSyncTimeCreditUseCase(networkMonitor),
        syncFromCloudUseCase = makeSyncFromCloudUseCase(networkMonitor),
        authRepository = fakeAuthRepo,
    )

    // =========================================================================
    // NetworkMonitor
    // =========================================================================

    @Test
    fun alwaysConnectedMonitor_returnsTrue() = runTest {
        assertTrue(AlwaysConnectedNetworkMonitor.isConnected())
    }

    @Test
    fun alwaysOfflineMonitor_returnsFalse() = runTest {
        assertFalse(AlwaysOfflineNetworkMonitor.isConnected())
    }

    // =========================================================================
    // SyncWorkoutsUseCase
    // =========================================================================

    @Test
    fun syncWorkouts_throwsForBlankUserId() = runTest {
        val useCase = makeSyncWorkoutsUseCase()
        assertFailsWith<IllegalArgumentException> { useCase("") }
        assertFailsWith<IllegalArgumentException> { useCase("  ") }
    }

    @Test
    fun syncWorkouts_throwsNoNetworkWhenOffline() = runTest {
        insertUser()
        val useCase = makeSyncWorkoutsUseCase(AlwaysOfflineNetworkMonitor)
        assertFailsWith<SyncException.NoNetwork> { useCase("user-1") }
    }

    @Test
    fun syncWorkouts_returnsEmptyResultWhenNoPendingSessions() = runTest {
        insertUser()
        insertSyncedSession()
        val useCase = makeSyncWorkoutsUseCase()

        val result = useCase("user-1")

        assertEquals(0, result.synced)
        assertEquals(0, result.skipped)
        assertEquals(0, result.failed)
        assertTrue(result.isFullSuccess)
    }

    @Test
    fun syncWorkouts_uploadsPendingSessionsSuccessfully() = runTest {
        insertUser()
        insertPendingSession(id = "s1")
        insertPendingSession(id = "s2")
        val useCase = makeSyncWorkoutsUseCase()

        val result = useCase("user-1")

        assertEquals(2, result.synced)
        assertEquals(0, result.failed)
        assertTrue(result.isFullSuccess)
    }

    @Test
    fun syncWorkouts_marksSessionsAsSyncedAfterUpload() = runTest {
        insertUser()
        insertPendingSession(id = "s1")
        val useCase = makeSyncWorkoutsUseCase()

        useCase("user-1")

        val session = sessionRepo.getById("s1")
        assertNotNull(session)
        assertEquals(SyncStatus.SYNCED, session.syncStatus)
    }

    @Test
    fun syncWorkouts_conflictResolution_localNewerWinsAndPatches() = runTest {
        insertUser()
        val laterInstant = baseInstant.plus(kotlin.time.Duration.parse("PT1H"))
        insertPendingSession(
            id = "s1",
            startedAt = laterInstant,
            endedAt = laterInstant.plus(kotlin.time.Duration.parse("PT5M")),
        )

        // Remote has an older version of the same session
        val remoteOlder = WorkoutSession(
            id = "s1",
            userId = "user-1",
            startedAt = baseInstant, // older
            endedAt = baseInstant.plus(kotlin.time.Duration.parse("PT5M")),
            pushUpCount = 5,
            earnedTimeCreditSeconds = 30L,
            quality = 0.5f,
            syncStatus = SyncStatus.SYNCED,
        )
        fakeSupabase.createSessionError = ApiException.Conflict("Conflict")
        fakeSupabase.getSessionResult = remoteOlder

        val useCase = makeSyncWorkoutsUseCase()
        val result = useCase("user-1")

        // Local was newer, so it should be patched and marked as skipped (conflict resolved)
        assertEquals(0, result.failed)
        assertTrue(fakeSupabase.updateSessionCalled)
    }

    @Test
    fun syncWorkouts_conflictResolution_remoteNewerWins_localMarkedSynced() = runTest {
        insertUser()
        insertPendingSession(id = "s1", startedAt = baseInstant)

        // Remote has a newer version
        val remoteNewer = WorkoutSession(
            id = "s1",
            userId = "user-1",
            startedAt = baseInstant.plus(kotlin.time.Duration.parse("PT1H")), // newer
            endedAt = baseInstant.plus(kotlin.time.Duration.parse("PT1H5M")),
            pushUpCount = 20,
            earnedTimeCreditSeconds = 120L,
            quality = 0.9f,
            syncStatus = SyncStatus.SYNCED,
        )
        fakeSupabase.createSessionError = ApiException.Conflict("Conflict")
        fakeSupabase.getSessionResult = remoteNewer

        val useCase = makeSyncWorkoutsUseCase()
        val result = useCase("user-1")

        assertEquals(0, result.failed)
        assertFalse(fakeSupabase.updateSessionCalled)
        // Local session should be marked as synced
        val local = sessionRepo.getById("s1")
        assertNotNull(local)
        assertEquals(SyncStatus.SYNCED, local.syncStatus)
    }

    @Test
    fun syncWorkouts_nonTransientError_marksSessionAsFailed() = runTest {
        insertUser()
        insertPendingSession(id = "s1")
        fakeSupabase.createSessionError = ApiException.Unauthorized("401")

        val useCase = makeSyncWorkoutsUseCase()
        val result = useCase("user-1")

        assertEquals(1, result.failed)
        assertFalse(result.isFullSuccess)
        val session = sessionRepo.getById("s1")
        assertNotNull(session)
        assertEquals(SyncStatus.FAILED, session.syncStatus)
    }

    @Test
    fun syncWorkouts_transientError_retriesAndSucceeds() = runTest {
        insertUser()
        insertPendingSession(id = "s1")
        // Fail once with a transient error, then succeed
        fakeSupabase.createSessionErrorCount = 1
        fakeSupabase.createSessionTransientError = ApiException.NetworkError("Network error")

        val useCase = makeSyncWorkoutsUseCase()
        val result = useCase("user-1")

        assertEquals(1, result.synced)
        assertEquals(0, result.failed)
    }

    @Test
    fun syncWorkouts_allRetriesExhausted_marksAsFailed() = runTest {
        insertUser()
        insertPendingSession(id = "s1")
        fakeSupabase.createSessionError = ApiException.NetworkError("Always fails")

        val useCase = makeSyncWorkoutsUseCase()
        val result = useCase("user-1")

        assertEquals(1, result.failed)
        assertFalse(result.isFullSuccess)
    }

    @Test
    fun syncWorkouts_onlySyncsPendingSessions_notSyncedOnes() = runTest {
        insertUser()
        insertPendingSession(id = "pending")
        insertSyncedSession(id = "already-synced")

        val useCase = makeSyncWorkoutsUseCase()
        val result = useCase("user-1")

        // Only the pending session should be uploaded
        assertEquals(1, result.synced)
        assertEquals(1, fakeSupabase.createSessionCallCount)
    }

    // =========================================================================
    // SyncTimeCreditUseCase
    // =========================================================================

    @Test
    fun syncTimeCredit_throwsForBlankUserId() = runTest {
        val useCase = makeSyncTimeCreditUseCase()
        assertFailsWith<IllegalArgumentException> { useCase("") }
    }

    @Test
    fun syncTimeCredit_throwsNoNetworkWhenOffline() = runTest {
        insertUser()
        val useCase = makeSyncTimeCreditUseCase(AlwaysOfflineNetworkMonitor)
        assertFailsWith<SyncException.NoNetwork> { useCase("user-1") }
    }

    @Test
    fun syncTimeCredit_returnsNoLocalDataWhenNoCreditExists() = runTest {
        insertUser()
        val useCase = makeSyncTimeCreditUseCase()

        val result = useCase("user-1")

        assertIs<SyncTimeCreditResult.NoLocalData>(result)
    }

    @Test
    fun syncTimeCredit_returnsAlreadySyncedWhenStatusIsSynced() = runTest {
        insertUser()
        val credit = TimeCredit(
            userId = "user-1",
            totalEarnedSeconds = 300L,
            totalSpentSeconds = 100L,
            lastUpdatedAt = baseInstant,
            syncStatus = SyncStatus.SYNCED,
        )
        timeCreditRepo.update(credit)
        val useCase = makeSyncTimeCreditUseCase()

        val result = useCase("user-1")

        assertIs<SyncTimeCreditResult.AlreadySynced>(result)
    }

    @Test
    fun syncTimeCredit_uploadsLocalCreditWhenRemoteIsNewer_pullsRemote() = runTest {
        insertUser()
        val localOlderInstant = baseInstant
        insertPendingCredit(lastUpdatedAt = localOlderInstant)

        // Remote is newer
        val remoteNewer = TimeCredit(
            userId = "user-1",
            totalEarnedSeconds = 500L,
            totalSpentSeconds = 200L,
            lastUpdatedAt = baseInstant.plus(kotlin.time.Duration.parse("PT1H")),
            syncStatus = SyncStatus.SYNCED,
        )
        fakeSupabase.getTimeCreditResult = remoteNewer

        val useCase = makeSyncTimeCreditUseCase()
        val result = useCase("user-1")

        assertIs<SyncTimeCreditResult.PulledFromRemote>(result)
        // Local should be updated with remote values
        val local = timeCreditRepo.get("user-1")
        assertNotNull(local)
        assertEquals(500L, local.totalEarnedSeconds)
        assertEquals(200L, local.totalSpentSeconds)
    }

    @Test
    fun syncTimeCredit_localNewerThanRemote_pushesLocalToRemote() = runTest {
        insertUser()
        val laterInstant = baseInstant.plus(kotlin.time.Duration.parse("PT1H"))
        insertPendingCredit(lastUpdatedAt = laterInstant)

        // Remote is older
        val remoteOlder = TimeCredit(
            userId = "user-1",
            totalEarnedSeconds = 100L,
            totalSpentSeconds = 50L,
            lastUpdatedAt = baseInstant, // older
            syncStatus = SyncStatus.SYNCED,
        )
        fakeSupabase.getTimeCreditResult = remoteOlder

        val useCase = makeSyncTimeCreditUseCase()
        val result = useCase("user-1")

        assertIs<SyncTimeCreditResult.Synced>(result)
        assertTrue(fakeSupabase.updateTimeCreditCalled)
        // Local should be marked as synced
        val local = timeCreditRepo.get("user-1")
        assertNotNull(local)
        assertEquals(SyncStatus.SYNCED, local.syncStatus)
    }

    @Test
    fun syncTimeCredit_noRemoteRecord_createsRemote() = runTest {
        insertUser()
        insertPendingCredit()
        fakeSupabase.getTimeCreditResult = null // No remote record

        val useCase = makeSyncTimeCreditUseCase()
        val result = useCase("user-1")

        // Should attempt to create/update remote and mark local as synced
        assertIs<SyncTimeCreditResult.Synced>(result)
    }

    @Test
    fun syncTimeCredit_nonTransientError_returnsFailedResult() = runTest {
        insertUser()
        insertPendingCredit()
        fakeSupabase.getTimeCreditError = ApiException.Forbidden("403")

        val useCase = makeSyncTimeCreditUseCase()
        val result = useCase("user-1")

        assertIs<SyncTimeCreditResult.Failed>(result)
        val local = timeCreditRepo.get("user-1")
        assertNotNull(local)
        assertEquals(SyncStatus.FAILED, local.syncStatus)
    }

    @Test
    fun syncTimeCredit_transientError_retriesAndSucceeds() = runTest {
        insertUser()
        insertPendingCredit()
        fakeSupabase.getTimeCreditErrorCount = 1
        fakeSupabase.getTimeCreditTransientError = ApiException.NetworkError("Network error")
        fakeSupabase.getTimeCreditResult = null // After retry, no remote record

        val useCase = makeSyncTimeCreditUseCase()
        val result = useCase("user-1")

        // Should succeed after retry
        assertIs<SyncTimeCreditResult.Synced>(result)
    }

    // =========================================================================
    // SyncFromCloudUseCase
    // =========================================================================

    @Test
    fun syncFromCloud_throwsForBlankUserId() = runTest {
        val useCase = makeSyncFromCloudUseCase()
        assertFailsWith<IllegalArgumentException> { useCase("") }
    }

    @Test
    fun syncFromCloud_throwsNoNetworkWhenOffline() = runTest {
        val useCase = makeSyncFromCloudUseCase(AlwaysOfflineNetworkMonitor)
        assertFailsWith<SyncException.NoNetwork> { useCase("user-1") }
    }

    @Test
    fun syncFromCloud_insertsNewRemoteSessionsLocally() = runTest {
        insertUser()
        val remoteSession = WorkoutSession(
            id = "remote-session",
            userId = "user-1",
            startedAt = baseInstant,
            endedAt = baseInstant.plus(kotlin.time.Duration.parse("PT5M")),
            pushUpCount = 15,
            earnedTimeCreditSeconds = 90L,
            quality = 0.85f,
            syncStatus = SyncStatus.SYNCED,
        )
        fakeSupabase.getSessionsResult = listOf(remoteSession)

        val useCase = makeSyncFromCloudUseCase()
        val result = useCase("user-1")

        assertEquals(1, result.sessionsDownloaded)
        assertEquals(1, result.sessionsInsertedOrUpdated)
        val local = sessionRepo.getById("remote-session")
        assertNotNull(local)
        assertEquals(SyncStatus.SYNCED, local.syncStatus)
        assertEquals(15, local.pushUpCount)
    }

    @Test
    fun syncFromCloud_remoteNewerThanLocal_overwritesLocal() = runTest {
        insertUser()
        // Insert an older local session
        insertPendingSession(id = "s1", startedAt = baseInstant, pushUpCount = 5)

        // Remote has a newer version
        val remoteNewer = WorkoutSession(
            id = "s1",
            userId = "user-1",
            startedAt = baseInstant.plus(kotlin.time.Duration.parse("PT1H")), // newer
            endedAt = baseInstant.plus(kotlin.time.Duration.parse("PT1H5M")),
            pushUpCount = 20,
            earnedTimeCreditSeconds = 120L,
            quality = 0.9f,
            syncStatus = SyncStatus.SYNCED,
        )
        fakeSupabase.getSessionsResult = listOf(remoteNewer)

        val useCase = makeSyncFromCloudUseCase()
        useCase("user-1")

        val local = sessionRepo.getById("s1")
        assertNotNull(local)
        // Local should be overwritten with remote values
        assertEquals(20, local.pushUpCount)
        assertEquals(SyncStatus.SYNCED, local.syncStatus)
    }

    @Test
    fun syncFromCloud_localNewerThanRemote_keepsLocal() = runTest {
        insertUser()
        val laterInstant = baseInstant.plus(kotlin.time.Duration.parse("PT1H"))
        // Insert a newer local session
        insertPendingSession(
            id = "s1",
            startedAt = laterInstant,
            endedAt = laterInstant.plus(kotlin.time.Duration.parse("PT5M")),
            pushUpCount = 25,
        )

        // Remote has an older version
        val remoteOlder = WorkoutSession(
            id = "s1",
            userId = "user-1",
            startedAt = baseInstant, // older
            endedAt = baseInstant.plus(kotlin.time.Duration.parse("PT5M")),
            pushUpCount = 5,
            earnedTimeCreditSeconds = 30L,
            quality = 0.5f,
            syncStatus = SyncStatus.SYNCED,
        )
        fakeSupabase.getSessionsResult = listOf(remoteOlder)

        val useCase = makeSyncFromCloudUseCase()
        useCase("user-1")

        val local = sessionRepo.getById("s1")
        assertNotNull(local)
        // Local should NOT be overwritten -- local is newer
        assertEquals(25, local.pushUpCount)
        assertEquals(SyncStatus.PENDING, local.syncStatus)
    }

    @Test
    fun syncFromCloud_insertsRemoteTimeCreditLocally() = runTest {
        insertUser()
        val remoteCredit = TimeCredit(
            userId = "user-1",
            totalEarnedSeconds = 600L,
            totalSpentSeconds = 200L,
            lastUpdatedAt = baseInstant,
            syncStatus = SyncStatus.SYNCED,
        )
        fakeSupabase.getTimeCreditResult = remoteCredit

        val useCase = makeSyncFromCloudUseCase()
        val result = useCase("user-1")

        assertTrue(result.timeCreditSynced)
        val local = timeCreditRepo.get("user-1")
        assertNotNull(local)
        assertEquals(600L, local.totalEarnedSeconds)
        assertEquals(SyncStatus.SYNCED, local.syncStatus)
    }

    @Test
    fun syncFromCloud_remoteTimeCreditNewerThanLocal_overwritesLocal() = runTest {
        insertUser()
        insertPendingCredit(earned = 100L, lastUpdatedAt = baseInstant)

        val remoteNewer = TimeCredit(
            userId = "user-1",
            totalEarnedSeconds = 500L,
            totalSpentSeconds = 100L,
            lastUpdatedAt = baseInstant.plus(kotlin.time.Duration.parse("PT1H")),
            syncStatus = SyncStatus.SYNCED,
        )
        fakeSupabase.getTimeCreditResult = remoteNewer

        val useCase = makeSyncFromCloudUseCase()
        useCase("user-1")

        val local = timeCreditRepo.get("user-1")
        assertNotNull(local)
        assertEquals(500L, local.totalEarnedSeconds)
        assertEquals(SyncStatus.SYNCED, local.syncStatus)
    }

    @Test
    fun syncFromCloud_localTimeCreditNewerThanRemote_keepsLocal() = runTest {
        insertUser()
        val laterInstant = baseInstant.plus(kotlin.time.Duration.parse("PT1H"))
        insertPendingCredit(earned = 300L, lastUpdatedAt = laterInstant)

        val remoteOlder = TimeCredit(
            userId = "user-1",
            totalEarnedSeconds = 100L,
            totalSpentSeconds = 50L,
            lastUpdatedAt = baseInstant, // older
            syncStatus = SyncStatus.SYNCED,
        )
        fakeSupabase.getTimeCreditResult = remoteOlder

        val useCase = makeSyncFromCloudUseCase()
        useCase("user-1")

        val local = timeCreditRepo.get("user-1")
        assertNotNull(local)
        // Local should NOT be overwritten
        assertEquals(300L, local.totalEarnedSeconds)
        assertEquals(SyncStatus.PENDING, local.syncStatus)
    }

    @Test
    fun syncFromCloud_noRemoteData_returnsSuccessWithZeroCounts() = runTest {
        insertUser()
        fakeSupabase.getSessionsResult = emptyList()
        fakeSupabase.getTimeCreditResult = null

        val useCase = makeSyncFromCloudUseCase()
        val result = useCase("user-1")

        assertEquals(0, result.sessionsDownloaded)
        assertEquals(0, result.sessionsInsertedOrUpdated)
        assertTrue(result.timeCreditSynced)
        assertTrue(result.isFullSuccess)
    }

    @Test
    fun syncFromCloud_networkErrorFetchingSessions_reportedInResult() = runTest {
        insertUser()
        fakeSupabase.getSessionsError = ApiException.NetworkError("Network error")

        val useCase = makeSyncFromCloudUseCase()
        val result = useCase("user-1")

        // Sessions failed to download (network error), but time credit may still succeed
        assertEquals(0, result.sessionsDownloaded)
        assertEquals(0, result.sessionsInsertedOrUpdated)
    }

    // =========================================================================
    // SyncManager
    // =========================================================================

    @Test
    fun syncManager_syncAll_skipsWhenUserNotAuthenticated() = runTest {
        fakeAuthRepo.currentUser = null
        val manager = makeSyncManager()

        val result = manager.syncAll()

        assertIs<SyncResult.Skipped>(result)
        assertEquals("User not authenticated", (result as SyncResult.Skipped).reason)
    }

    @Test
    fun syncManager_syncAll_completedWithNoNetworkErrorsWhenOffline() = runTest {
        insertUser()
        fakeAuthRepo.currentUser = User(
            id = "user-1",
            email = "test@example.com",
            displayName = "Test",
            createdAt = baseInstant,
            lastSyncedAt = baseInstant,
        )
        val manager = makeSyncManager(AlwaysOfflineNetworkMonitor)

        val result = manager.syncAll()

        // SyncManager does not short-circuit on offline; each use-case throws
        // SyncException.NoNetwork which is captured in the error fields.
        assertIs<SyncResult.Completed>(result)
        assertIs<SyncException.NoNetwork>((result as SyncResult.Completed).workoutsError)
        assertIs<SyncException.NoNetwork>(result.timeCreditError)
        assertIs<SyncException.NoNetwork>(result.fromCloudError)
        assertFalse(result.isFullSuccess)
    }

    @Test
    fun syncManager_syncAll_completesSuccessfullyWithAuthenticatedUser() = runTest {
        insertUser()
        fakeAuthRepo.currentUser = User(
            id = "user-1",
            email = "test@example.com",
            displayName = "Test",
            createdAt = baseInstant,
            lastSyncedAt = baseInstant,
        )
        insertPendingSession(id = "s1")
        insertPendingCredit()

        val manager = makeSyncManager()
        val result = manager.syncAll()

        assertIs<SyncResult.Completed>(result)
        assertNull((result as SyncResult.Completed).workoutsError)
        assertNull(result.timeCreditError)
        assertNull(result.fromCloudError)
    }

    @Test
    fun syncManager_syncAfterWorkout_doesNotRunFromCloudSync() = runTest {
        insertUser()
        fakeAuthRepo.currentUser = User(
            id = "user-1",
            email = "test@example.com",
            displayName = "Test",
            createdAt = baseInstant,
            lastSyncedAt = baseInstant,
        )
        insertPendingSession(id = "s1")

        val manager = makeSyncManager()
        val result = manager.syncAfterWorkout()

        assertIs<SyncResult.Completed>(result)
        // fromCloud should be null since syncAfterWorkout doesn't run it
        assertNull((result as SyncResult.Completed).fromCloud)
        assertNull(result.fromCloudError)
    }

    @Test
    fun syncManager_syncFromCloud_onlyRunsFromCloudSync() = runTest {
        insertUser()
        fakeAuthRepo.currentUser = User(
            id = "user-1",
            email = "test@example.com",
            displayName = "Test",
            createdAt = baseInstant,
            lastSyncedAt = baseInstant,
        )

        val manager = makeSyncManager()
        val result = manager.syncFromCloud()

        assertIs<SyncResult.Completed>(result)
        // workouts and timeCredit should be null
        assertNull((result as SyncResult.Completed).workouts)
        assertNull(result.timeCredit)
    }

    @Test
    fun syncManager_syncAll_isFullSuccessWhenAllUseCasesSucceed() = runTest {
        insertUser()
        fakeAuthRepo.currentUser = User(
            id = "user-1",
            email = "test@example.com",
            displayName = "Test",
            createdAt = baseInstant,
            lastSyncedAt = baseInstant,
        )

        val manager = makeSyncManager()
        val result = manager.syncAll()

        assertIs<SyncResult.Completed>(result)
        assertTrue((result as SyncResult.Completed).isFullSuccess)
    }

    @Test
    fun syncManager_syncAll_isNotFullSuccessWhenUseCaseFails() = runTest {
        insertUser()
        fakeAuthRepo.currentUser = User(
            id = "user-1",
            email = "test@example.com",
            displayName = "Test",
            createdAt = baseInstant,
            lastSyncedAt = baseInstant,
        )
        insertPendingSession(id = "s1")
        // Make all create calls fail with a non-transient error
        fakeSupabase.createSessionError = ApiException.Unauthorized("401")

        val manager = makeSyncManager()
        val result = manager.syncAll()

        assertIs<SyncResult.Completed>(result)
        // workouts completed but with failures
        assertFalse((result as SyncResult.Completed).isFullSuccess)
    }

    @Test
    fun syncManager_periodicSync_startsAndStops() = runTest {
        val manager = makeSyncManager()

        assertFalse(manager.isPeriodicSyncRunning)

        manager.startPeriodicSync()
        assertTrue(manager.isPeriodicSyncRunning)

        manager.stopPeriodicSync()
        assertFalse(manager.isPeriodicSyncRunning)
    }

    @Test
    fun syncManager_startPeriodicSync_calledTwice_replacesExistingJob() = runTest {
        val manager = makeSyncManager()

        manager.startPeriodicSync()
        val firstJobActive = manager.isPeriodicSyncRunning

        manager.startPeriodicSync() // Should replace, not throw
        val secondJobActive = manager.isPeriodicSyncRunning

        assertTrue(firstJobActive)
        assertTrue(secondJobActive)

        manager.stopPeriodicSync()
    }
}

// =============================================================================
// Test doubles
// =============================================================================

/**
 * In-memory fake for [CloudSyncApi].
 *
 * Configurable success responses and errors for each operation.
 * Tracks call counts and whether specific methods were invoked.
 */
class FakeCloudSyncApi : CloudSyncApi {
    // WorkoutSession
    var getSessionsResult: List<WorkoutSession> = emptyList()
    var getSessionsError: Exception? = null
    var getSessionResult: WorkoutSession? = null
    var createSessionError: Exception? = null
    var createSessionTransientError: Exception? = null
    var createSessionErrorCount: Int = 0
    var createSessionCallCount: Int = 0
    var updateSessionCalled: Boolean = false

    // TimeCredit
    var getTimeCreditResult: TimeCredit? = null
    var getTimeCreditError: Exception? = null
    var getTimeCreditTransientError: Exception? = null
    var getTimeCreditErrorCount: Int = 0
    var updateTimeCreditCalled: Boolean = false

    private var createSessionCallsSoFar = 0
    private var getTimeCreditCallsSoFar = 0

    override suspend fun getWorkoutSessions(): List<WorkoutSession> {
        getSessionsError?.let { throw it }
        return getSessionsResult
    }

    override suspend fun getWorkoutSession(id: String): WorkoutSession {
        return getSessionResult
            ?: throw ApiException.NotFound("Session not found: $id", "WorkoutSession", id)
    }

    override suspend fun getWorkoutSessionsByDateRange(
        from: kotlinx.datetime.Instant,
        to: kotlinx.datetime.Instant,
    ): List<WorkoutSession> = getSessionsResult

    override suspend fun createWorkoutSession(request: CreateWorkoutSessionRequest): WorkoutSession {
        createSessionCallCount++
        createSessionCallsSoFar++

        if (createSessionTransientError != null && createSessionCallsSoFar <= createSessionErrorCount) {
            throw createSessionTransientError!!
        }
        createSessionError?.let { throw it }

        return WorkoutSession(
            id = request.userId + "-created",
            userId = request.userId,
            startedAt = kotlinx.datetime.Instant.parse(request.startedAt),
            endedAt = request.endedAt?.let { kotlinx.datetime.Instant.parse(it) },
            pushUpCount = request.pushUpCount,
            earnedTimeCreditSeconds = request.earnedTimeCredits.toLong(),
            quality = request.quality,
            syncStatus = SyncStatus.SYNCED,
        )
    }

    override suspend fun updateWorkoutSession(
        id: String,
        request: UpdateWorkoutSessionRequest,
    ): WorkoutSession {
        updateSessionCalled = true
        return getSessionResult ?: WorkoutSession(
            id = id,
            userId = "user-1",
            startedAt = kotlinx.datetime.Instant.fromEpochMilliseconds(1_700_000_000_000L),
            endedAt = null,
            pushUpCount = request.pushUpCount ?: 0,
            earnedTimeCreditSeconds = request.earnedTimeCredits?.toLong() ?: 0L,
            quality = request.quality ?: 0f,
            syncStatus = SyncStatus.SYNCED,
        )
    }

    override suspend fun getTimeCredit(userId: String): TimeCredit? {
        getTimeCreditCallsSoFar++

        if (getTimeCreditTransientError != null && getTimeCreditCallsSoFar <= getTimeCreditErrorCount) {
            throw getTimeCreditTransientError!!
        }
        getTimeCreditError?.let { throw it }
        return getTimeCreditResult
    }

    override suspend fun updateTimeCredit(
        userId: String,
        request: UpdateTimeCreditRequest,
    ): TimeCredit {
        updateTimeCreditCalled = true
        return TimeCredit(
            userId = userId,
            totalEarnedSeconds = request.totalEarnedSeconds ?: 0L,
            totalSpentSeconds = request.totalSpentSeconds ?: 0L,
            lastUpdatedAt = kotlinx.datetime.Instant.fromEpochMilliseconds(1_700_000_000_000L),
            syncStatus = SyncStatus.SYNCED,
        )
    }
}

/**
 * In-memory fake for [AuthRepository].
 *
 * Returns a configurable [currentUser] without any database or network calls.
 */
class FakeAuthRepository : AuthRepository {
    var currentUser: User? = null

    override suspend fun registerWithEmail(email: String, password: String): User =
        throw UnsupportedOperationException()

    override suspend fun loginWithEmail(email: String, password: String): User =
        throw UnsupportedOperationException()

    override suspend fun loginWithApple(idToken: String): User =
        throw UnsupportedOperationException()

    override suspend fun loginWithGoogle(idToken: String): User =
        throw UnsupportedOperationException()

    override suspend fun logout(clearLocalData: Boolean) {}

    override suspend fun getCurrentUser(): User? = currentUser

    override suspend fun getCurrentToken(): AuthToken? = null

    override suspend fun refreshToken(): AuthToken =
        throw UnsupportedOperationException()
}
