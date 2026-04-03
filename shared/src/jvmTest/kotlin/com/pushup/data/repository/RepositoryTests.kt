package com.pushup.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.RunEventParticipantDTO
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.PushUpRecord
import com.pushup.domain.model.RunEvent
import com.pushup.domain.model.RunEventParticipant
import com.pushup.domain.model.RunEventStatus
import com.pushup.domain.model.RunMode
import com.pushup.domain.model.RunParticipantRole
import com.pushup.domain.model.RunParticipantStatus
import com.pushup.domain.model.RunVisibility
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.model.User
import com.pushup.domain.model.UserSettings
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.usecase.sync.AlwaysConnectedNetworkMonitor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.StandardTestDispatcher
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
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Integration tests for all repository implementations using an in-memory
 * SQLite database (JDBC driver).
 *
 * Each test gets a fresh database instance so tests are fully isolated.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RepositoryTests {

    private lateinit var database: PushUpDatabase
    private val testDispatcher = StandardTestDispatcher()

    /** Fixed clock for deterministic timestamps in tests. */
    private val fixedClock = object : Clock {
        var nowMs: Long = 1_700_000_000_000L
        override fun now(): Instant = Instant.fromEpochMilliseconds(nowMs)
    }

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        PushUpDatabase.Schema.create(driver)
        // Enable foreign key enforcement (required for ON DELETE CASCADE)
        driver.execute(null, "PRAGMA foreign_keys = ON;", 0)
        database = PushUpDatabase(driver)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // =========================================================================
    // Helper factories
    // =========================================================================

    private fun testUser(
        id: String = "user-1",
        email: String = "test@example.com",
        username: String? = null,
        displayName: String = "Test User",
        createdAt: Instant = Instant.fromEpochMilliseconds(1_700_000_000_000L),
        lastSyncedAt: Instant = Instant.fromEpochMilliseconds(1_700_000_000_000L),
    ) = User(id = id, email = email, username = username, displayName = displayName,
             createdAt = createdAt, lastSyncedAt = lastSyncedAt)

    private fun testSession(
        id: String = "session-1",
        userId: String = "user-1",
        startedAt: Instant = Instant.fromEpochMilliseconds(1_700_000_000_000L),
        endedAt: Instant? = Instant.fromEpochMilliseconds(1_700_000_300_000L),
        pushUpCount: Int = 25,
        earnedTimeCreditSeconds: Long = 150L,
        quality: Float = 0.85f,
        syncStatus: SyncStatus = SyncStatus.PENDING,
    ) = WorkoutSession(id, userId, startedAt, endedAt, pushUpCount, earnedTimeCreditSeconds, quality, syncStatus)

    private fun testRecord(
        id: String = "record-1",
        sessionId: String = "session-1",
        timestamp: Instant = Instant.fromEpochMilliseconds(1_700_000_050_000L),
        durationMs: Long = 1200L,
        depthScore: Float = 0.9f,
        formScore: Float = 0.85f,
    ) = PushUpRecord(id, sessionId, timestamp, durationMs, depthScore, formScore)

    // =========================================================================
    // UserRepositoryImpl Tests
    // =========================================================================

    @Test
    fun userRepo_saveAndGetCurrentUser() = runTest {
        val repo = UserRepositoryImpl(database, testDispatcher)
        val user = testUser()

        repo.saveUser(user)
        val result = repo.getCurrentUser()

        assertNotNull(result)
        assertEquals(user.id, result.id)
        assertEquals(user.email, result.email)
        assertEquals(user.displayName, result.displayName)
    }

    @Test
    fun userRepo_getCurrentUser_returnsNullWhenEmpty() = runTest {
        val repo = UserRepositoryImpl(database, testDispatcher)

        val result = repo.getCurrentUser()

        assertNull(result)
    }

    @Test
    fun userRepo_updateUser() = runTest {
        val repo = UserRepositoryImpl(database, testDispatcher)
        val user = testUser()
        repo.saveUser(user)

        val updated = user.copy(
            email = "new@example.com",
            displayName = "Updated User",
        )
        repo.updateUser(updated)

        val result = repo.getCurrentUser()
        assertNotNull(result)
        assertEquals("new@example.com", result.email)
        assertEquals("Updated User", result.displayName)
    }

    @Test
    fun userRepo_observeCurrentUser_emitsUpdates() = runTest {
        val repo = UserRepositoryImpl(database, testDispatcher)
        val user = testUser()

        repo.saveUser(user)
        val observed = repo.observeCurrentUser().first()

        assertNotNull(observed)
        assertEquals(user.id, observed.id)
    }

    @Test
    fun userRepo_observeCurrentUser_emitsNullWhenEmpty() = runTest {
        val repo = UserRepositoryImpl(database, testDispatcher)

        val observed = repo.observeCurrentUser().first()

        assertNull(observed)
    }

    // =========================================================================
    // WorkoutSessionRepositoryImpl Tests
    // =========================================================================

    private fun setupUserForWorkouts() {
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

    @Test
    fun sessionRepo_saveAndGetById() = runTest {
        setupUserForWorkouts()
        val repo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)
        val session = testSession()

        repo.save(session)
        val result = repo.getById(session.id)

        assertNotNull(result)
        assertEquals(session.id, result.id)
        assertEquals(session.userId, result.userId)
        assertEquals(session.pushUpCount, result.pushUpCount)
        assertEquals(session.quality, result.quality, 0.001f)
    }

    @Test
    fun sessionRepo_getById_returnsNullForMissing() = runTest {
        val repo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)

        val result = repo.getById("nonexistent")

        assertNull(result)
    }

    @Test
    fun sessionRepo_saveUpdatesExisting() = runTest {
        setupUserForWorkouts()
        val repo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)
        val session = testSession()
        repo.save(session)

        val updated = session.copy(
            pushUpCount = 50,
            earnedTimeCreditSeconds = 300L,
            quality = 0.95f,
        )
        repo.save(updated)

        val result = repo.getById(session.id)
        assertNotNull(result)
        assertEquals(50, result.pushUpCount)
        assertEquals(300L, result.earnedTimeCreditSeconds)
        assertEquals(0.95f, result.quality, 0.001f)
    }

    @Test
    fun sessionRepo_getAllByUserId() = runTest {
        setupUserForWorkouts()
        val repo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)

        repo.save(testSession(id = "s1"))
        repo.save(testSession(id = "s2"))
        repo.save(testSession(id = "s3"))

        val results = repo.getAllByUserId("user-1")

        assertEquals(3, results.size)
    }

    @Test
    fun sessionRepo_getAllByUserId_returnsEmptyForUnknownUser() = runTest {
        val repo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)

        val results = repo.getAllByUserId("unknown-user")

        assertTrue(results.isEmpty())
    }

    @Test
    fun sessionRepo_getByDateRange() = runTest {
        setupUserForWorkouts()
        val repo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)

        val baseTime = 1_700_000_000_000L
        repo.save(testSession(
            id = "s1",
            startedAt = Instant.fromEpochMilliseconds(baseTime),
            endedAt = Instant.fromEpochMilliseconds(baseTime + 300_000),
        ))
        repo.save(testSession(
            id = "s2",
            startedAt = Instant.fromEpochMilliseconds(baseTime + 100_000),
            endedAt = Instant.fromEpochMilliseconds(baseTime + 400_000),
        ))
        repo.save(testSession(
            id = "s3",
            startedAt = Instant.fromEpochMilliseconds(baseTime + 500_000),
            endedAt = Instant.fromEpochMilliseconds(baseTime + 800_000),
        ))

        val results = repo.getByDateRange(
            userId = "user-1",
            from = Instant.fromEpochMilliseconds(baseTime),
            to = Instant.fromEpochMilliseconds(baseTime + 200_000),
        )

        assertEquals(2, results.size)
    }

    @Test
    fun sessionRepo_getUnsyncedSessions() = runTest {
        setupUserForWorkouts()
        val repo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)

        repo.save(testSession(id = "s1", syncStatus = SyncStatus.PENDING))
        repo.save(testSession(id = "s2", syncStatus = SyncStatus.SYNCED))
        repo.save(testSession(id = "s3", syncStatus = SyncStatus.FAILED))

        val results = repo.getUnsyncedSessions("user-1")

        assertEquals(2, results.size)
        assertTrue(results.none { it.syncStatus == SyncStatus.SYNCED })
    }

    @Test
    fun sessionRepo_markAsSynced() = runTest {
        setupUserForWorkouts()
        val repo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)
        repo.save(testSession(id = "s1", syncStatus = SyncStatus.PENDING))

        repo.markAsSynced("s1")

        val result = repo.getById("s1")
        assertNotNull(result)
        assertEquals(SyncStatus.SYNCED, result.syncStatus)
    }

    @Test
    fun sessionRepo_delete() = runTest {
        setupUserForWorkouts()
        val repo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)
        repo.save(testSession(id = "s1"))

        repo.delete("s1")

        assertNull(repo.getById("s1"))
    }

    @Test
    fun sessionRepo_observeAllByUserId_emitsUpdates() = runTest {
        setupUserForWorkouts()
        val repo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)
        repo.save(testSession(id = "s1"))

        val observed = repo.observeAllByUserId("user-1").first()

        assertEquals(1, observed.size)
        assertEquals("s1", observed.first().id)
    }

    // =========================================================================
    // PushUpRecordRepositoryImpl Tests
    // =========================================================================

    private fun setupSessionForRecords() {
        setupUserForWorkouts()
        database.databaseQueries.insertWorkoutSession(
            id = "session-1",
            userId = "user-1",
            startedAt = 1_700_000_000_000L,
            endedAt = 1_700_000_300_000L,
            pushUpCount = 25L,
            earnedTimeCredits = 150L,
            quality = 0.85,
            syncStatus = "pending",
            updatedAt = 1_700_000_000_000L,
        )
    }

    @Test
    fun recordRepo_saveAndGetBySessionId() = runTest {
        setupSessionForRecords()
        val repo = PushUpRecordRepositoryImpl(database, testDispatcher)
        val record = testRecord()

        repo.save(record)
        val results = repo.getBySessionId("session-1")

        assertEquals(1, results.size)
        assertEquals(record.id, results.first().id)
        assertEquals(record.durationMs, results.first().durationMs)
        assertEquals(record.depthScore, results.first().depthScore, 0.001f)
        assertEquals(record.formScore, results.first().formScore, 0.001f)
    }

    @Test
    fun recordRepo_saveAll_insertsMultipleRecordsInTransaction() = runTest {
        setupSessionForRecords()
        val repo = PushUpRecordRepositoryImpl(database, testDispatcher)
        val records = listOf(
            testRecord(id = "r1", timestamp = Instant.fromEpochMilliseconds(1_700_000_050_000L)),
            testRecord(id = "r2", timestamp = Instant.fromEpochMilliseconds(1_700_000_051_000L)),
            testRecord(id = "r3", timestamp = Instant.fromEpochMilliseconds(1_700_000_052_000L)),
        )

        repo.saveAll(records)

        val results = repo.getBySessionId("session-1")
        assertEquals(3, results.size)
    }

    @Test
    fun recordRepo_getBySessionId_orderedByTimestamp() = runTest {
        setupSessionForRecords()
        val repo = PushUpRecordRepositoryImpl(database, testDispatcher)
        // Insert in reverse order
        repo.save(testRecord(id = "r3", timestamp = Instant.fromEpochMilliseconds(1_700_000_053_000L)))
        repo.save(testRecord(id = "r1", timestamp = Instant.fromEpochMilliseconds(1_700_000_051_000L)))
        repo.save(testRecord(id = "r2", timestamp = Instant.fromEpochMilliseconds(1_700_000_052_000L)))

        val results = repo.getBySessionId("session-1")

        assertEquals("r1", results[0].id)
        assertEquals("r2", results[1].id)
        assertEquals("r3", results[2].id)
    }

    @Test
    fun recordRepo_getBySessionId_returnsEmptyForUnknownSession() = runTest {
        val repo = PushUpRecordRepositoryImpl(database, testDispatcher)

        val results = repo.getBySessionId("nonexistent")

        assertTrue(results.isEmpty())
    }

    @Test
    fun recordRepo_delete() = runTest {
        setupSessionForRecords()
        val repo = PushUpRecordRepositoryImpl(database, testDispatcher)
        repo.save(testRecord(id = "r1"))

        repo.delete("r1")

        assertTrue(repo.getBySessionId("session-1").isEmpty())
    }

    // =========================================================================
    // TimeCreditRepositoryImpl Tests
    // =========================================================================

    @Test
    fun creditRepo_getReturnsNullWhenEmpty() = runTest {
        setupUserForWorkouts()
        val repo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)

        val result = repo.get("user-1")

        assertNull(result)
    }

    @Test
    fun creditRepo_updateAndGet() = runTest {
        setupUserForWorkouts()
        val repo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)

        val credit = TimeCredit(
            userId = "user-1",
            totalEarnedSeconds = 3600L,
            totalSpentSeconds = 1800L,
            dailyEarnedSeconds = 1800L,
            dailySpentSeconds = 0L,
            lastResetAt = null,
            lastUpdatedAt = Instant.fromEpochMilliseconds(1_700_000_000_000L),
            syncStatus = SyncStatus.PENDING,
        )
        repo.update(credit)

        val result = repo.get("user-1")
        assertNotNull(result)
        assertEquals(3600L, result.totalEarnedSeconds)
        assertEquals(1800L, result.totalSpentSeconds)
        assertEquals(1800L, result.availableSeconds)
    }

    @Test
    fun creditRepo_updateExistingPreservesRowId() = runTest {
        setupUserForWorkouts()
        val repo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)

        val credit1 = TimeCredit(
            userId = "user-1",
            totalEarnedSeconds = 1000L,
            totalSpentSeconds = 0L,
            dailyEarnedSeconds = 1000L,
            dailySpentSeconds = 0L,
            lastResetAt = null,
            lastUpdatedAt = Instant.fromEpochMilliseconds(1_700_000_000_000L),
            syncStatus = SyncStatus.PENDING,
        )
        repo.update(credit1)

        val credit2 = credit1.copy(totalEarnedSeconds = 2000L)
        repo.update(credit2)

        val result = repo.get("user-1")
        assertNotNull(result)
        assertEquals(2000L, result.totalEarnedSeconds)
    }

    @Test
    fun creditRepo_addEarnedSeconds() = runTest {
        setupUserForWorkouts()
        val repo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)

        repo.addEarnedSeconds("user-1", 100L)
        repo.addEarnedSeconds("user-1", 200L)

        val result = repo.get("user-1")
        assertNotNull(result)
        assertEquals(300L, result.totalEarnedSeconds)
        assertEquals(0L, result.totalSpentSeconds)
    }

    @Test
    fun creditRepo_addSpentSeconds() = runTest {
        setupUserForWorkouts()
        val repo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)
        repo.addEarnedSeconds("user-1", 500L)

        repo.addSpentSeconds("user-1", 200L)

        val result = repo.get("user-1")
        assertNotNull(result)
        assertEquals(500L, result.totalEarnedSeconds)
        assertEquals(200L, result.totalSpentSeconds)
        assertEquals(300L, result.availableSeconds)
    }

    @Test
    fun creditRepo_addEarnedSeconds_requiresPositive() = runTest {
        setupUserForWorkouts()
        val repo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)

        assertFailsWith<IllegalArgumentException> {
            repo.addEarnedSeconds("user-1", 0L)
        }
        assertFailsWith<IllegalArgumentException> {
            repo.addEarnedSeconds("user-1", -10L)
        }
    }

    @Test
    fun creditRepo_addSpentSeconds_requiresPositive() = runTest {
        setupUserForWorkouts()
        val repo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)

        assertFailsWith<IllegalArgumentException> {
            repo.addSpentSeconds("user-1", 0L)
        }
    }

    @Test
    fun creditRepo_markAsSynced() = runTest {
        setupUserForWorkouts()
        val repo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)
        repo.addEarnedSeconds("user-1", 100L)

        repo.markAsSynced("user-1")

        val result = repo.get("user-1")
        assertNotNull(result)
        assertEquals(SyncStatus.SYNCED, result.syncStatus)
    }

    @Test
    fun creditRepo_markAsSynced_noop_whenNoCreditExists() = runTest {
        setupUserForWorkouts()
        val repo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)

        // Should not throw even when no credit exists
        repo.markAsSynced("user-1")

        assertNull(repo.get("user-1"))
    }

    @Test
    fun creditRepo_observeCredit() = runTest {
        setupUserForWorkouts()
        val repo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)
        repo.addEarnedSeconds("user-1", 500L)

        val observed = repo.observeCredit("user-1").first()

        assertNotNull(observed)
        assertEquals(500L, observed.totalEarnedSeconds)
    }

    @Test
    fun creditRepo_addSpentSeconds_createsNewRowIfMissing() = runTest {
        setupUserForWorkouts()
        val repo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)

        repo.addSpentSeconds("user-1", 50L)

        val result = repo.get("user-1")
        assertNotNull(result)
        assertEquals(0L, result.totalEarnedSeconds)
        assertEquals(50L, result.totalSpentSeconds)
    }

    // =========================================================================
    // UserSettingsRepositoryImpl Tests
    // =========================================================================

    @Test
    fun settingsRepo_getReturnsNullWhenEmpty() = runTest {
        setupUserForWorkouts()
        val repo = UserSettingsRepositoryImpl(database, testDispatcher)

        val result = repo.get("user-1")

        assertNull(result)
    }

    @Test
    fun settingsRepo_updateAndGet() = runTest {
        setupUserForWorkouts()
        val repo = UserSettingsRepositoryImpl(database, testDispatcher)

        val settings = UserSettings(
            userId = "user-1",
            pushUpsPerMinuteCredit = 15,
            qualityMultiplierEnabled = true,
            dailyCreditCapSeconds = 3600L,
        )
        repo.update(settings)

        val result = repo.get("user-1")
        assertNotNull(result)
        assertEquals(15, result.pushUpsPerMinuteCredit)
        assertTrue(result.qualityMultiplierEnabled)
        assertEquals(3600L, result.dailyCreditCapSeconds)
    }

    @Test
    fun settingsRepo_updateExistingSettings() = runTest {
        setupUserForWorkouts()
        val repo = UserSettingsRepositoryImpl(database, testDispatcher)

        val initial = UserSettings.default("user-1")
        repo.update(initial)

        val updated = initial.copy(
            pushUpsPerMinuteCredit = 20,
            qualityMultiplierEnabled = false,
            dailyCreditCapSeconds = 7200L,
        )
        repo.update(updated)

        val result = repo.get("user-1")
        assertNotNull(result)
        assertEquals(20, result.pushUpsPerMinuteCredit)
        assertEquals(false, result.qualityMultiplierEnabled)
        assertEquals(7200L, result.dailyCreditCapSeconds)
    }

    @Test
    fun settingsRepo_updateWithNullCap() = runTest {
        setupUserForWorkouts()
        val repo = UserSettingsRepositoryImpl(database, testDispatcher)

        val settings = UserSettings(
            userId = "user-1",
            pushUpsPerMinuteCredit = 10,
            qualityMultiplierEnabled = false,
            dailyCreditCapSeconds = null,
        )
        repo.update(settings)

        val result = repo.get("user-1")
        assertNotNull(result)
        assertNull(result.dailyCreditCapSeconds)
    }

    @Test
    fun settingsRepo_observeSettings() = runTest {
        setupUserForWorkouts()
        val repo = UserSettingsRepositoryImpl(database, testDispatcher)
        repo.update(UserSettings.default("user-1"))

        val observed = repo.observeSettings("user-1").first()

        assertNotNull(observed)
        assertEquals("user-1", observed.userId)
    }

    @Test
    fun settingsRepo_observeSettings_emitsNullWhenEmpty() = runTest {
        setupUserForWorkouts()
        val repo = UserSettingsRepositoryImpl(database, testDispatcher)

        val observed = repo.observeSettings("user-1").first()

        assertNull(observed)
    }

    // =========================================================================
    // StatsRepositoryImpl Tests
    // =========================================================================

    private val utcTimeZone = TimeZone.UTC

    private fun createStatsRepo(): StatsRepositoryImpl {
        val timeCreditRepo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)
        return StatsRepositoryImpl(
            database = database,
            timeCreditRepository = timeCreditRepo,
            dispatcher = testDispatcher,
            timeZone = utcTimeZone,
            clock = fixedClock,
        )
    }

    @Test
    fun statsRepo_getDailyStats_returnsNullForEmptyDay() = runTest {
        setupUserForWorkouts()
        val repo = createStatsRepo()

        val result = repo.getDailyStats("user-1", LocalDate(2023, 11, 15))

        assertNull(result)
    }

    @Test
    fun statsRepo_getDailyStats_aggregatesSessions() = runTest {
        setupUserForWorkouts()
        val repo = createStatsRepo()

        // 2023-11-15 in UTC: starts at 1700006400000
        val dayStart = 1_700_006_400_000L // 2023-11-15T00:00:00Z
        val sessionRepo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)
        sessionRepo.save(testSession(
            id = "s1",
            startedAt = Instant.fromEpochMilliseconds(dayStart + 3600_000),
            endedAt = Instant.fromEpochMilliseconds(dayStart + 3900_000),
            pushUpCount = 20,
            earnedTimeCreditSeconds = 120L,
            quality = 0.8f,
        ))
        sessionRepo.save(testSession(
            id = "s2",
            startedAt = Instant.fromEpochMilliseconds(dayStart + 7200_000),
            endedAt = Instant.fromEpochMilliseconds(dayStart + 7500_000),
            pushUpCount = 30,
            earnedTimeCreditSeconds = 180L,
            quality = 0.9f,
        ))

        val result = repo.getDailyStats("user-1", LocalDate(2023, 11, 15))

        assertNotNull(result)
        assertEquals(LocalDate(2023, 11, 15), result.date)
        assertEquals(50, result.totalPushUps)
        assertEquals(2, result.totalSessions)
        assertEquals(300L, result.totalEarnedSeconds)
        assertEquals(0.85f, result.averageQuality, 0.001f)
        // averagePushUpsPerSession: (20 + 30) / 2 = 25
        assertEquals(25f, result.averagePushUpsPerSession, 0.001f)
        // bestSession: max(20, 30) = 30
        assertEquals(30, result.bestSession)
    }

    @Test
    fun statsRepo_getWeeklyStats_returnsNullForEmptyWeek() = runTest {
        setupUserForWorkouts()
        val repo = createStatsRepo()

        // A Monday in 2023
        val result = repo.getWeeklyStats("user-1", LocalDate(2023, 11, 13))

        assertNull(result)
    }

    @Test
    fun statsRepo_getWeeklyStats_aggregatesAcrossDays() = runTest {
        setupUserForWorkouts()
        val repo = createStatsRepo()
        val sessionRepo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)

        // Week of 2023-11-13 (Monday) to 2023-11-19 (Sunday)
        // Monday: 1699833600000 = 2023-11-13T00:00:00Z
        val mondayStart = 1_699_833_600_000L
        val tuesdayStart = mondayStart + 86_400_000L

        sessionRepo.save(testSession(
            id = "s1",
            startedAt = Instant.fromEpochMilliseconds(mondayStart + 3600_000),
            endedAt = Instant.fromEpochMilliseconds(mondayStart + 3900_000),
            pushUpCount = 20,
            earnedTimeCreditSeconds = 120L,
            quality = 0.8f,
        ))
        sessionRepo.save(testSession(
            id = "s2",
            startedAt = Instant.fromEpochMilliseconds(tuesdayStart + 3600_000),
            endedAt = Instant.fromEpochMilliseconds(tuesdayStart + 3900_000),
            pushUpCount = 30,
            earnedTimeCreditSeconds = 180L,
            quality = 0.9f,
        ))

        val result = repo.getWeeklyStats("user-1", LocalDate(2023, 11, 13))

        assertNotNull(result)
        assertEquals(LocalDate(2023, 11, 13), result.weekStartDate)
        assertEquals(50, result.totalPushUps)
        assertEquals(2, result.totalSessions)
        assertEquals(300L, result.totalEarnedSeconds)
        assertEquals(7, result.dailyBreakdown.size)
        assertEquals(2, result.activeDays)
        // averagePushUpsPerSession: (20 + 30) / 2 = 25
        assertEquals(25f, result.averagePushUpsPerSession, 0.001f)
        // bestSession: max(20, 30) = 30
        assertEquals(30, result.bestSession)
    }

    @Test
    fun statsRepo_getMonthlyStats_returnsNullForEmptyMonth() = runTest {
        setupUserForWorkouts()
        val repo = createStatsRepo()

        val result = repo.getMonthlyStats("user-1", 11, 2023)

        assertNull(result)
    }

    @Test
    fun statsRepo_getMonthlyStats_aggregatesAcrossWeeks() = runTest {
        setupUserForWorkouts()
        val repo = createStatsRepo()
        val sessionRepo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)

        // November 2023
        // Nov 1 = 1698796800000 (Wednesday)
        val nov1 = 1_698_796_800_000L
        val nov15 = nov1 + 14 * 86_400_000L

        sessionRepo.save(testSession(
            id = "s1",
            startedAt = Instant.fromEpochMilliseconds(nov1 + 3600_000),
            endedAt = Instant.fromEpochMilliseconds(nov1 + 3900_000),
            pushUpCount = 20,
            earnedTimeCreditSeconds = 120L,
            quality = 0.8f,
        ))
        sessionRepo.save(testSession(
            id = "s2",
            startedAt = Instant.fromEpochMilliseconds(nov15 + 3600_000),
            endedAt = Instant.fromEpochMilliseconds(nov15 + 3900_000),
            pushUpCount = 30,
            earnedTimeCreditSeconds = 180L,
            quality = 0.9f,
        ))

        val result = repo.getMonthlyStats("user-1", 11, 2023)

        assertNotNull(result)
        assertEquals(11, result.month)
        assertEquals(2023, result.year)
        assertEquals(50, result.totalPushUps)
        assertEquals(2, result.totalSessions)
        assertEquals(300L, result.totalEarnedSeconds)
        assertTrue(result.weeklyBreakdown.isNotEmpty())
        // averagePushUpsPerSession: (20 + 30) / 2 = 25
        assertEquals(25f, result.averagePushUpsPerSession, 0.001f)
        // bestSession: max(20, 30) = 30
        assertEquals(30, result.bestSession)
    }

    @Test
    fun statsRepo_getTotalStats_returnsNullForNoData() = runTest {
        setupUserForWorkouts()
        val repo = createStatsRepo()

        val result = repo.getTotalStats("user-1")

        assertNull(result)
    }

    @Test
    fun statsRepo_getTotalStats_aggregatesAllSessions() = runTest {
        setupUserForWorkouts()
        val sessionRepo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)
        val timeCreditRepo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)

        val day1 = 1_700_006_400_000L // 2023-11-15T00:00:00Z
        val day2 = day1 + 86_400_000L  // 2023-11-16T00:00:00Z

        sessionRepo.save(testSession(
            id = "s1",
            startedAt = Instant.fromEpochMilliseconds(day1 + 3600_000),
            endedAt = Instant.fromEpochMilliseconds(day1 + 3900_000),
            pushUpCount = 20,
            earnedTimeCreditSeconds = 120L,
            quality = 0.8f,
        ))
        sessionRepo.save(testSession(
            id = "s2",
            startedAt = Instant.fromEpochMilliseconds(day2 + 3600_000),
            endedAt = Instant.fromEpochMilliseconds(day2 + 3900_000),
            pushUpCount = 30,
            earnedTimeCreditSeconds = 180L,
            quality = 0.9f,
        ))

        timeCreditRepo.addEarnedSeconds("user-1", 300L)
        timeCreditRepo.addSpentSeconds("user-1", 100L)

        // Set clock to 2023-11-16 so the last training day is "today"
        fixedClock.nowMs = day2 + 3600_000
        val repo = createStatsRepo()

        val result = repo.getTotalStats("user-1")

        assertNotNull(result)
        assertEquals("user-1", result.userId)
        assertEquals(50, result.totalPushUps)
        assertEquals(2, result.totalSessions)
        assertEquals(300L, result.totalEarnedSeconds)
        assertEquals(100L, result.totalSpentSeconds)
        assertEquals(0.85f, result.averageQuality, 0.001f)
        // averagePushUpsPerSession: (20 + 30) / 2 = 25
        assertEquals(25f, result.averagePushUpsPerSession, 0.001f)
        // bestSession: max(20, 30) = 30
        assertEquals(30, result.bestSession)
        // Two consecutive days, last day is today => streak of 2
        assertEquals(2, result.currentStreakDays)
        assertEquals(2, result.longestStreakDays)
    }

    @Test
    fun statsRepo_getTotalStats_calculatesStreaksCorrectly() = runTest {
        setupUserForWorkouts()
        val sessionRepo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)

        // Sessions on days 0-2 (consecutive), gap on day 3, then days 4-5
        // day 0 = 2023-11-15, day 5 = 2023-11-20
        val baseDay = 1_700_006_400_000L // 2023-11-15T00:00:00Z
        val oneDay = 86_400_000L

        for (i in 0 until 3) {
            sessionRepo.save(testSession(
                id = "s${i + 1}",
                startedAt = Instant.fromEpochMilliseconds(baseDay + i * oneDay + 3600_000),
                endedAt = Instant.fromEpochMilliseconds(baseDay + i * oneDay + 3900_000),
                pushUpCount = 10,
                earnedTimeCreditSeconds = 60L,
                quality = 0.8f,
            ))
        }
        // Gap on day 3
        for (i in 4 until 6) {
            sessionRepo.save(testSession(
                id = "s${i + 1}",
                startedAt = Instant.fromEpochMilliseconds(baseDay + i * oneDay + 3600_000),
                endedAt = Instant.fromEpochMilliseconds(baseDay + i * oneDay + 3900_000),
                pushUpCount = 10,
                earnedTimeCreditSeconds = 60L,
                quality = 0.8f,
            ))
        }

        // Set clock to day 5 (2023-11-20) so the last training day is "today"
        fixedClock.nowMs = baseDay + 5 * oneDay + 3600_000
        val repo = createStatsRepo()

        val result = repo.getTotalStats("user-1")

        assertNotNull(result)
        // Current streak: days 4 and 5 = 2 (last day is today)
        assertEquals(2, result.currentStreakDays)
        // Longest streak: days 0, 1, 2 = 3
        assertEquals(3, result.longestStreakDays)
    }

    // =========================================================================
    // StatsRepositoryImpl.calculateStreaks Unit Tests
    // =========================================================================

    @Test
    fun calculateStreaks_emptyList_returnsZeroZero() {
        val repo = createStatsRepo()
        val today = LocalDate(2023, 11, 20)

        val (current, longest) = repo.calculateStreaks(emptyList(), today)

        assertEquals(0, current)
        assertEquals(0, longest)
    }

    @Test
    fun calculateStreaks_singleDayIsToday_returnsOneOne() {
        val repo = createStatsRepo()
        val today = LocalDate(2023, 11, 20)

        val (current, longest) = repo.calculateStreaks(listOf(today), today)

        assertEquals(1, current)
        assertEquals(1, longest)
    }

    @Test
    fun calculateStreaks_singleDayIsYesterday_returnsOneOne() {
        val repo = createStatsRepo()
        val today = LocalDate(2023, 11, 20)
        val yesterday = LocalDate(2023, 11, 19)

        val (current, longest) = repo.calculateStreaks(listOf(yesterday), today)

        assertEquals(1, current)
        assertEquals(1, longest)
    }

    @Test
    fun calculateStreaks_singleDayTwoDaysAgo_returnsZeroOne() {
        val repo = createStatsRepo()
        val today = LocalDate(2023, 11, 20)
        val twoDaysAgo = LocalDate(2023, 11, 18)

        val (current, longest) = repo.calculateStreaks(listOf(twoDaysAgo), today)

        assertEquals(0, current)
        assertEquals(1, longest)
    }

    @Test
    fun calculateStreaks_consecutiveDaysEndingToday_correctCurrentAndLongest() {
        val repo = createStatsRepo()
        val today = LocalDate(2023, 11, 20)
        val dates = listOf(
            LocalDate(2023, 11, 18),
            LocalDate(2023, 11, 19),
            LocalDate(2023, 11, 20),
        )

        val (current, longest) = repo.calculateStreaks(dates, today)

        assertEquals(3, current)
        assertEquals(3, longest)
    }

    @Test
    fun calculateStreaks_gapBeforeLastRun_currentIsLastRunLength() {
        val repo = createStatsRepo()
        // today = 2023-11-20, last run = days 18+19+20 (3 days), earlier run = days 14+15+16 (3 days)
        val today = LocalDate(2023, 11, 20)
        val dates = listOf(
            LocalDate(2023, 11, 14),
            LocalDate(2023, 11, 15),
            LocalDate(2023, 11, 16),
            // gap on 17
            LocalDate(2023, 11, 18),
            LocalDate(2023, 11, 19),
            LocalDate(2023, 11, 20),
        )

        val (current, longest) = repo.calculateStreaks(dates, today)

        assertEquals(3, current)
        assertEquals(3, longest)
    }

    @Test
    fun calculateStreaks_longerEarlierRun_longestExceedsCurrentCorrectly() {
        val repo = createStatsRepo()
        // today = 2023-11-20, last run = days 19+20 (2), earlier run = days 14+15+16+17 (4)
        val today = LocalDate(2023, 11, 20)
        val dates = listOf(
            LocalDate(2023, 11, 14),
            LocalDate(2023, 11, 15),
            LocalDate(2023, 11, 16),
            LocalDate(2023, 11, 17),
            // gap on 18
            LocalDate(2023, 11, 19),
            LocalDate(2023, 11, 20),
        )

        val (current, longest) = repo.calculateStreaks(dates, today)

        assertEquals(2, current)
        assertEquals(4, longest)
    }

    @Test
    fun calculateStreaks_lastDayNotTodayOrYesterday_currentIsZero() {
        val repo = createStatsRepo()
        val today = LocalDate(2023, 11, 20)
        val dates = listOf(
            LocalDate(2023, 11, 14),
            LocalDate(2023, 11, 15),
            LocalDate(2023, 11, 16),
        )

        val (current, longest) = repo.calculateStreaks(dates, today)

        assertEquals(0, current)
        assertEquals(3, longest)
    }

    // =========================================================================
    // RepositoryException (Error Wrapping) Tests
    // =========================================================================

    @Test
    fun repositoryException_hasCause() {
        val cause = IllegalStateException("DB error")
        val exception = RepositoryException("Failed operation", cause)

        assertEquals("Failed operation", exception.message)
        assertEquals(cause, exception.cause)
    }

    @Test
    fun repositoryException_withoutCause() {
        val exception = RepositoryException("Standalone error")

        assertEquals("Standalone error", exception.message)
        assertNull(exception.cause)
    }

    // =========================================================================
    // Cross-Repository Integration Tests
    // =========================================================================

    @Test
    fun crossRepo_workoutSessionWithRecords() = runTest {
        setupSessionForRecords()
        val sessionRepo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)
        val recordRepo = PushUpRecordRepositoryImpl(database, testDispatcher)

        // Session was inserted via setupSessionForRecords
        val records = listOf(
            testRecord(id = "r1", timestamp = Instant.fromEpochMilliseconds(1_700_000_050_000L)),
            testRecord(id = "r2", timestamp = Instant.fromEpochMilliseconds(1_700_000_051_000L)),
            testRecord(id = "r3", timestamp = Instant.fromEpochMilliseconds(1_700_000_052_000L)),
        )
        recordRepo.saveAll(records)

        val session = sessionRepo.getById("session-1")
        val fetchedRecords = recordRepo.getBySessionId("session-1")

        assertNotNull(session)
        assertEquals(3, fetchedRecords.size)
        assertTrue(fetchedRecords.all { it.sessionId == session.id })
    }

    // =========================================================================
    // Edge-Case Tests
    // =========================================================================

    @Test
    fun userRepo_saveDuplicateId_throwsRepositoryException() = runTest {
        val repo = UserRepositoryImpl(database, testDispatcher)
        repo.saveUser(testUser())

        assertFailsWith<RepositoryException> {
            repo.saveUser(testUser()) // same ID again
        }
    }

    @Test
    fun recordRepo_saveDuplicateId_throwsRepositoryException() = runTest {
        setupSessionForRecords()
        val repo = PushUpRecordRepositoryImpl(database, testDispatcher)
        repo.save(testRecord(id = "r1"))

        assertFailsWith<RepositoryException> {
            repo.save(testRecord(id = "r1")) // same ID again
        }
    }

    @Test
    fun sessionRepo_saveWithInvalidUserId_throwsRepositoryException() = runTest {
        val repo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)

        assertFailsWith<RepositoryException> {
            repo.save(testSession(userId = "nonexistent-user"))
        }
    }

    @Test
    fun recordRepo_saveAll_emptyList_succeeds() = runTest {
        val repo = PushUpRecordRepositoryImpl(database, testDispatcher)

        // Should not throw for an empty list
        repo.saveAll(emptyList())
    }

    @Test
    fun statsRepo_getMonthlyStats_december_crossesYearBoundary() = runTest {
        setupUserForWorkouts()
        val repo = createStatsRepo()
        val sessionRepo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)

        // Dec 15, 2023 = 1702598400000 (UTC)
        val dec15 = 1_702_598_400_000L
        sessionRepo.save(testSession(
            id = "s1",
            startedAt = Instant.fromEpochMilliseconds(dec15 + 3600_000),
            endedAt = Instant.fromEpochMilliseconds(dec15 + 3900_000),
            pushUpCount = 20,
            earnedTimeCreditSeconds = 120L,
            quality = 0.8f,
        ))

        val result = repo.getMonthlyStats("user-1", 12, 2023)

        assertNotNull(result)
        assertEquals(12, result.month)
        assertEquals(2023, result.year)
        assertEquals(20, result.totalPushUps)
    }

    @Test
    fun crossRepo_deletingSessionCascadesRecords() = runTest {
        setupSessionForRecords()
        val sessionRepo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)
        val recordRepo = PushUpRecordRepositoryImpl(database, testDispatcher)

        recordRepo.saveAll(listOf(
            testRecord(id = "r1", timestamp = Instant.fromEpochMilliseconds(1_700_000_050_000L)),
            testRecord(id = "r2", timestamp = Instant.fromEpochMilliseconds(1_700_000_051_000L)),
        ))

        // Delete the session -- ON DELETE CASCADE should remove records
        sessionRepo.delete("session-1")

        val records = recordRepo.getBySessionId("session-1")
        assertTrue(records.isEmpty())
    }

    @Test
    fun runEventRepo_getParticipants_resyncsExistingEventWithoutDuplicateInsert() = runTest {
        val now = Instant.fromEpochMilliseconds(1_700_000_000_000L)
        val eventId = "event-1"
        val userId = "user-1"

        database.databaseQueries.insertUser(
            id = userId,
            email = "runner@example.com",
            username = null,
            displayName = "Runner",
            avatarUrl = null,
            avatarVisibility = "everyone",
            createdAt = now.toEpochMilliseconds(),
            syncedAt = now.toEpochMilliseconds(),
        )

        val repo = RunEventRepositoryImpl(
            database = database,
            dispatcher = testDispatcher,
            clock = fixedClock,
            cloudSyncApi = object : CloudSyncApi {
                override suspend fun getRunEventParticipants(eventId: String): List<RunEventParticipantDTO> =
                    listOf(
                        RunEventParticipantDTO(
                            id = "participant-1",
                            eventId = eventId,
                            userId = userId,
                            role = "organizer",
                            status = "accepted",
                            invitedBy = null,
                            invitedAt = now.toString(),
                            respondedAt = now.toString(),
                            checkedInAt = null,
                            createdAt = now.toString(),
                            updatedAt = now.toString(),
                        )
                    )
            },
            networkMonitor = AlwaysConnectedNetworkMonitor,
        )

        repo.create(
            event = RunEvent(
                id = eventId,
                createdBy = userId,
                title = "Morning Run",
                description = null,
                mode = RunMode.BASE,
                visibility = RunVisibility.FRIENDS,
                plannedStartAt = now,
                plannedEndAt = null,
                checkInOpensAt = now,
                locationName = null,
                status = RunEventStatus.PLANNED,
                createdAt = now,
                updatedAt = now,
            ),
            participants = listOf(
                RunEventParticipant(
                    id = "participant-1",
                    eventId = eventId,
                    userId = userId,
                    role = RunParticipantRole.ORGANIZER,
                    status = RunParticipantStatus.ACCEPTED,
                    invitedBy = null,
                    invitedAt = now,
                    respondedAt = now,
                    checkedInAt = null,
                    createdAt = now,
                    updatedAt = now,
                )
            ),
        )

        val participants = repo.getParticipants(eventId)

        assertEquals(1, participants.size)
        assertEquals(userId, participants.single().userId)
        assertEquals("Morning Run", repo.getById(eventId)?.title)
    }
}
