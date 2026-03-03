package com.pushup.domain.usecase

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.pushup.data.repository.PushUpRecordRepositoryImpl
import com.pushup.data.repository.StatsRepositoryImpl
import com.pushup.data.repository.TimeCreditRepositoryImpl
import com.pushup.data.repository.UserRepositoryImpl
import com.pushup.data.repository.UserSettingsRepositoryImpl
import com.pushup.data.repository.WorkoutSessionRepositoryImpl
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.model.User
import com.pushup.domain.model.UserSettings
import com.pushup.domain.model.WorkoutSession
import com.pushup.domain.repository.PushUpRecordRepository
import com.pushup.domain.repository.StatsRepository
import com.pushup.domain.repository.TimeCreditRepository
import com.pushup.domain.repository.UserRepository
import com.pushup.domain.repository.UserSettingsRepository
import com.pushup.domain.repository.WorkoutSessionRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
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
 * Integration tests for all use-case implementations (Tasks 1A.7 - 1A.13).
 *
 * Each test uses a fresh in-memory SQLite database so tests are fully isolated.
 * A fixed [Clock] and sequential [IdGenerator] are injected for determinism.
 * Repository fields are typed as interfaces to decouple tests from implementations.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class UseCaseTests {

    private lateinit var database: PushUpDatabase
    private val testDispatcher = StandardTestDispatcher()

    /** Fixed clock that can be advanced between operations. Volatile for safe publication. */
    private val fixedClock = object : Clock {
        @Volatile var nowMs: Long = 1_700_000_000_000L
        override fun now(): Instant = Instant.fromEpochMilliseconds(nowMs)
    }

    /** Sequential ID generator for deterministic IDs in tests. */
    private var idCounter = 0
    private val sequentialIdGenerator = IdGenerator { "id-${++idCounter}" }

    // Repositories typed as interfaces to decouple tests from implementations
    private lateinit var userRepo: UserRepository
    private lateinit var sessionRepo: WorkoutSessionRepository
    private lateinit var recordRepo: PushUpRecordRepository
    private lateinit var timeCreditRepo: TimeCreditRepository
    private lateinit var settingsRepo: UserSettingsRepository
    private lateinit var statsRepo: StatsRepository

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        idCounter = 0
        fixedClock.nowMs = 1_700_000_000_000L

        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        PushUpDatabase.Schema.create(driver)
        driver.execute(null, "PRAGMA foreign_keys = ON;", 0)
        database = PushUpDatabase(driver)

        userRepo = UserRepositoryImpl(database, testDispatcher)
        sessionRepo = WorkoutSessionRepositoryImpl(database, testDispatcher, fixedClock)
        recordRepo = PushUpRecordRepositoryImpl(database, testDispatcher)
        timeCreditRepo = TimeCreditRepositoryImpl(database, testDispatcher, fixedClock)
        settingsRepo = UserSettingsRepositoryImpl(database, testDispatcher)
        statsRepo = StatsRepositoryImpl(
            database = database,
            timeCreditRepository = timeCreditRepo,
            dispatcher = testDispatcher,
            timeZone = TimeZone.UTC,
            clock = fixedClock,
        )
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // =========================================================================
    // Helper factories
    // =========================================================================

    private fun testUser(id: String = "user-1") = User(
        id = id,
        email = "test@example.com",
        displayName = "Test User",
        createdAt = Instant.fromEpochMilliseconds(1_700_000_000_000L),
        lastSyncedAt = Instant.fromEpochMilliseconds(1_700_000_000_000L),
    )

    private suspend fun insertUser(id: String = "user-1"): User {
        val user = testUser(id)
        userRepo.saveUser(user)
        return user
    }

    private suspend fun insertSession(
        id: String = "session-1",
        userId: String = "user-1",
        pushUpCount: Int = 0,
        quality: Float = 0.0f,
        endedAt: Instant? = null,
        startedAt: Instant = Instant.fromEpochMilliseconds(1_700_000_000_000L),
        earnedTimeCreditSeconds: Long = 0L,
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

    private fun makeFinishUseCase(tz: TimeZone = TimeZone.UTC) = FinishWorkoutUseCase(
        sessionRepo, recordRepo, timeCreditRepo, settingsRepo, fixedClock, tz,
    )

    // =========================================================================
    // Task 1A.7: GetOrCreateLocalUserUseCase
    // =========================================================================

    @Test
    fun getOrCreateLocalUser_createsGuestUserWhenNoneExists() = runTest {
        val useCase = GetOrCreateLocalUserUseCase(userRepo, fixedClock, sequentialIdGenerator)

        val user = useCase()

        assertNotNull(user)
        assertEquals("id-1", user.id)
        assertEquals("Guest", user.displayName)
        assertEquals("guest@local", user.email)
        assertEquals(fixedClock.now(), user.createdAt)
    }

    @Test
    fun getOrCreateLocalUser_persistsGuestUserToDatabase() = runTest {
        val useCase = GetOrCreateLocalUserUseCase(userRepo, fixedClock, sequentialIdGenerator)

        useCase()

        val stored = userRepo.getCurrentUser()
        assertNotNull(stored)
        assertEquals("Guest", stored.displayName)
    }

    @Test
    fun getOrCreateLocalUser_returnsExistingUserWhenPresent() = runTest {
        val existingUser = insertUser("existing-user")
        val useCase = GetOrCreateLocalUserUseCase(userRepo, fixedClock, sequentialIdGenerator)

        val result = useCase()

        assertEquals(existingUser.id, result.id)
        assertEquals(existingUser.email, result.email)
        // ID generator should NOT have been called (no new user created)
        assertEquals(0, idCounter)
    }

    @Test
    fun getOrCreateLocalUser_calledTwice_returnsSameUser() = runTest {
        val useCase = GetOrCreateLocalUserUseCase(userRepo, fixedClock, sequentialIdGenerator)

        val first = useCase()
        val second = useCase()

        assertEquals(first.id, second.id)
        // Only one user should have been created
        assertEquals(1, idCounter)
    }

    // =========================================================================
    // Task 1A.8: StartWorkoutUseCase
    // =========================================================================

    @Test
    fun startWorkout_createsNewSession() = runTest {
        insertUser()
        val useCase = StartWorkoutUseCase(sessionRepo, fixedClock, sequentialIdGenerator)

        val session = useCase("user-1")

        assertNotNull(session)
        assertEquals("id-1", session.id)
        assertEquals("user-1", session.userId)
        assertEquals(fixedClock.now(), session.startedAt)
        assertNull(session.endedAt)
        assertEquals(0, session.pushUpCount)
        assertEquals(0L, session.earnedTimeCreditSeconds)
        assertEquals(0.0f, session.quality)
        assertEquals(SyncStatus.PENDING, session.syncStatus)
    }

    @Test
    fun startWorkout_persistsSessionToDatabase() = runTest {
        insertUser()
        val useCase = StartWorkoutUseCase(sessionRepo, fixedClock, sequentialIdGenerator)

        val session = useCase("user-1")

        val stored = sessionRepo.getById(session.id)
        assertNotNull(stored)
        assertEquals(session.id, stored.id)
        assertTrue(stored.isActive)
    }

    @Test
    fun startWorkout_throwsWhenActiveSessionExists() = runTest {
        insertUser()
        insertSession(id = "active-session", userId = "user-1", endedAt = null)
        val useCase = StartWorkoutUseCase(sessionRepo, fixedClock, sequentialIdGenerator)

        assertFailsWith<WorkoutAlreadyActiveException> {
            useCase("user-1")
        }
    }

    @Test
    fun startWorkout_allowsNewSessionAfterPreviousEnded() = runTest {
        insertUser()
        insertSession(
            id = "ended-session",
            userId = "user-1",
            endedAt = Instant.fromEpochMilliseconds(1_700_000_300_000L),
        )
        val useCase = StartWorkoutUseCase(sessionRepo, fixedClock, sequentialIdGenerator)

        val session = useCase("user-1")

        assertNotNull(session)
        assertTrue(session.isActive)
    }

    @Test
    fun startWorkout_requiresNonBlankUserId() = runTest {
        val useCase = StartWorkoutUseCase(sessionRepo, fixedClock, sequentialIdGenerator)

        assertFailsWith<IllegalArgumentException> {
            useCase("")
        }
    }

    // =========================================================================
    // Task 1A.9: RecordPushUpUseCase
    // =========================================================================

    @Test
    fun recordPushUp_createsRecordAndUpdatesSession() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1")
        val useCase = RecordPushUpUseCase(sessionRepo, recordRepo, fixedClock, sequentialIdGenerator)

        val record = useCase(
            sessionId = "session-1",
            durationMs = 1200L,
            depthScore = 0.9f,
            formScore = 0.85f,
        )

        assertNotNull(record)
        assertEquals("id-1", record.id)
        assertEquals("session-1", record.sessionId)
        assertEquals(1200L, record.durationMs)
        assertEquals(0.9f, record.depthScore, 0.001f)
        assertEquals(0.85f, record.formScore, 0.001f)
    }

    @Test
    fun recordPushUp_incrementsPushUpCount() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1")
        val useCase = RecordPushUpUseCase(sessionRepo, recordRepo, fixedClock, sequentialIdGenerator)

        useCase("session-1", 1000L, 0.8f, 0.8f)
        useCase("session-1", 1100L, 0.9f, 0.9f)
        useCase("session-1", 1200L, 0.7f, 0.7f)

        val session = sessionRepo.getById("session-1")
        assertNotNull(session)
        assertEquals(3, session.pushUpCount)
    }

    @Test
    fun recordPushUp_updatesQualityAsRunningAverage() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1")
        val useCase = RecordPushUpUseCase(sessionRepo, recordRepo, fixedClock, sequentialIdGenerator)

        useCase("session-1", 1000L, 0.8f, 0.6f)
        useCase("session-1", 1100L, 0.9f, 0.8f)

        val session = sessionRepo.getById("session-1")
        assertNotNull(session)
        // Average of 0.6 and 0.8 = 0.7
        assertEquals(0.7f, session.quality, 0.001f)
    }

    @Test
    fun recordPushUp_throwsWhenSessionNotFound() = runTest {
        val useCase = RecordPushUpUseCase(sessionRepo, recordRepo, fixedClock, sequentialIdGenerator)

        assertFailsWith<SessionNotFoundException> {
            useCase("nonexistent-session", 1000L, 0.8f, 0.8f)
        }
    }

    @Test
    fun recordPushUp_throwsWhenSessionAlreadyEnded() = runTest {
        insertUser()
        insertSession(
            id = "ended-session",
            userId = "user-1",
            endedAt = Instant.fromEpochMilliseconds(1_700_000_300_000L),
        )
        val useCase = RecordPushUpUseCase(sessionRepo, recordRepo, fixedClock, sequentialIdGenerator)

        assertFailsWith<SessionAlreadyEndedException> {
            useCase("ended-session", 1000L, 0.8f, 0.8f)
        }
    }

    @Test
    fun recordPushUp_persistsRecordToDatabase() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1")
        val useCase = RecordPushUpUseCase(sessionRepo, recordRepo, fixedClock, sequentialIdGenerator)

        val record = useCase("session-1", 1000L, 0.8f, 0.75f)

        val stored = recordRepo.getBySessionId("session-1")
        assertEquals(1, stored.size)
        assertEquals(record.id, stored.first().id)
    }

    @Test
    fun recordPushUp_throwsForZeroDurationMs() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1")
        val useCase = RecordPushUpUseCase(sessionRepo, recordRepo, fixedClock, sequentialIdGenerator)

        assertFailsWith<IllegalArgumentException> {
            useCase("session-1", 0L, 0.8f, 0.8f)
        }
    }

    @Test
    fun recordPushUp_throwsForNegativeDurationMs() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1")
        val useCase = RecordPushUpUseCase(sessionRepo, recordRepo, fixedClock, sequentialIdGenerator)

        assertFailsWith<IllegalArgumentException> {
            useCase("session-1", -1L, 0.8f, 0.8f)
        }
    }

    @Test
    fun recordPushUp_throwsForDepthScoreOutOfRange() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1")
        val useCase = RecordPushUpUseCase(sessionRepo, recordRepo, fixedClock, sequentialIdGenerator)

        assertFailsWith<IllegalArgumentException> {
            useCase("session-1", 1000L, -0.1f, 0.8f)
        }
        assertFailsWith<IllegalArgumentException> {
            useCase("session-1", 1000L, 1.1f, 0.8f)
        }
    }

    @Test
    fun recordPushUp_throwsForFormScoreOutOfRange() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1")
        val useCase = RecordPushUpUseCase(sessionRepo, recordRepo, fixedClock, sequentialIdGenerator)

        assertFailsWith<IllegalArgumentException> {
            useCase("session-1", 1000L, 0.8f, -0.1f)
        }
        assertFailsWith<IllegalArgumentException> {
            useCase("session-1", 1000L, 0.8f, 1.1f)
        }
    }

    // =========================================================================
    // Task 1A.10: FinishWorkoutUseCase
    // =========================================================================

    @Test
    fun finishWorkout_setsEndedAtAndReturnsWorkoutSummary() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1", pushUpCount = 10)
        settingsRepo.update(UserSettings.default("user-1"))

        val summary = makeFinishUseCase().invoke("session-1")

        assertNotNull(summary.session.endedAt)
        assertEquals(fixedClock.now(), summary.session.endedAt)
        assertEquals("session-1", summary.session.id)
    }

    @Test
    fun finishWorkout_calculatesEarnedCreditsCorrectly() = runTest {
        insertUser()
        // 10 push-ups, rate = 10 push-ups/min -> 1 minute = 60 seconds, no multiplier
        insertSession(id = "session-1", userId = "user-1", pushUpCount = 10)
        settingsRepo.update(
            UserSettings(
                userId = "user-1",
                pushUpsPerMinuteCredit = 10,
                qualityMultiplierEnabled = false,
                dailyCreditCapSeconds = null,
            ),
        )

        val summary = makeFinishUseCase().invoke("session-1")

        // 10 / 10 * 60 = 60 seconds
        assertEquals(60L, summary.earnedCredits)
    }

    @Test
    fun finishWorkout_zeroPushUpsEarnsZeroCredits() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1", pushUpCount = 0)
        settingsRepo.update(UserSettings.default("user-1"))

        val summary = makeFinishUseCase().invoke("session-1")

        assertEquals(0L, summary.earnedCredits)
    }

    @Test
    fun finishWorkout_appliesQualityMultiplierHighQuality() = runTest {
        insertUser()
        // 10 push-ups, quality > 0.8 -> 1.5x multiplier
        insertSession(id = "session-1", userId = "user-1", pushUpCount = 10, quality = 0.9f)
        settingsRepo.update(
            UserSettings(
                userId = "user-1",
                pushUpsPerMinuteCredit = 10,
                qualityMultiplierEnabled = true,
                dailyCreditCapSeconds = null,
            ),
        )

        val summary = makeFinishUseCase().invoke("session-1")

        // 10 / 10 * 60 * 1.5 = 90 seconds
        assertEquals(90L, summary.earnedCredits)
    }

    @Test
    fun finishWorkout_appliesQualityMultiplierLowQuality() = runTest {
        insertUser()
        // 10 push-ups, quality < 0.5 -> 0.7x multiplier
        insertSession(id = "session-1", userId = "user-1", pushUpCount = 10, quality = 0.3f)
        settingsRepo.update(
            UserSettings(
                userId = "user-1",
                pushUpsPerMinuteCredit = 10,
                qualityMultiplierEnabled = true,
                dailyCreditCapSeconds = null,
            ),
        )

        val summary = makeFinishUseCase().invoke("session-1")

        // 10 / 10 * 60 * 0.7 = 42 seconds
        assertEquals(42L, summary.earnedCredits)
    }

    @Test
    fun finishWorkout_noQualityMultiplierWhenDisabled() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1", pushUpCount = 10, quality = 0.9f)
        settingsRepo.update(
            UserSettings(
                userId = "user-1",
                pushUpsPerMinuteCredit = 10,
                qualityMultiplierEnabled = false,
                dailyCreditCapSeconds = null,
            ),
        )

        val summary = makeFinishUseCase().invoke("session-1")

        // No multiplier: 10 / 10 * 60 = 60 seconds
        assertEquals(60L, summary.earnedCredits)
    }

    @Test
    fun finishWorkout_respectsDailyCreditCap() = runTest {
        insertUser()
        // 100 push-ups would earn 600 seconds, but cap is 300
        insertSession(id = "session-1", userId = "user-1", pushUpCount = 100)
        settingsRepo.update(
            UserSettings(
                userId = "user-1",
                pushUpsPerMinuteCredit = 10,
                qualityMultiplierEnabled = false,
                dailyCreditCapSeconds = 300L,
            ),
        )

        val summary = makeFinishUseCase().invoke("session-1")

        assertEquals(300L, summary.earnedCredits)
    }

    @Test
    fun finishWorkout_dailyCapAlreadyFullyConsumed_earnsZero() = runTest {
        insertUser()
        // A previous session already earned the full cap today
        val dayStart = 1_700_006_400_000L // 2023-11-15T00:00:00Z
        insertSession(
            id = "earlier-session",
            userId = "user-1",
            pushUpCount = 50,
            earnedTimeCreditSeconds = 300L,
            startedAt = Instant.fromEpochMilliseconds(dayStart + 3600_000L),
            endedAt = Instant.fromEpochMilliseconds(dayStart + 3900_000L),
        )
        // Current session starts later the same day
        fixedClock.nowMs = dayStart + 7200_000L
        insertSession(
            id = "current-session",
            userId = "user-1",
            pushUpCount = 50,
            startedAt = Instant.fromEpochMilliseconds(dayStart + 7200_000L),
        )
        settingsRepo.update(
            UserSettings(
                userId = "user-1",
                pushUpsPerMinuteCredit = 10,
                qualityMultiplierEnabled = false,
                dailyCreditCapSeconds = 300L,
            ),
        )

        val summary = makeFinishUseCase().invoke("current-session")

        assertEquals(0L, summary.earnedCredits)
    }

    @Test
    fun finishWorkout_addsEarnedSecondsToTimeCredit() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1", pushUpCount = 10)
        settingsRepo.update(
            UserSettings(
                userId = "user-1",
                pushUpsPerMinuteCredit = 10,
                qualityMultiplierEnabled = false,
                dailyCreditCapSeconds = null,
            ),
        )

        makeFinishUseCase().invoke("session-1")

        val credit = timeCreditRepo.get("user-1")
        assertNotNull(credit)
        assertEquals(60L, credit.totalEarnedSeconds)
    }

    @Test
    fun finishWorkout_throwsWhenSessionNotFound() = runTest {
        assertFailsWith<SessionNotFoundException> {
            makeFinishUseCase().invoke("nonexistent-session")
        }
    }

    @Test
    fun finishWorkout_throwsWhenSessionAlreadyEnded() = runTest {
        insertUser()
        insertSession(
            id = "ended-session",
            userId = "user-1",
            endedAt = Instant.fromEpochMilliseconds(1_700_000_300_000L),
        )

        assertFailsWith<SessionAlreadyEndedException> {
            makeFinishUseCase().invoke("ended-session")
        }
    }

    @Test
    fun finishWorkout_throwsForBlankSessionId() = runTest {
        assertFailsWith<IllegalArgumentException> {
            makeFinishUseCase().invoke("  ")
        }
    }

    @Test
    fun finishWorkout_includesAllRecordsInSummary() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1")
        settingsRepo.update(UserSettings.default("user-1"))
        val recordUseCase = RecordPushUpUseCase(
            sessionRepo, recordRepo, fixedClock, sequentialIdGenerator,
        )
        recordUseCase("session-1", 1000L, 0.8f, 0.8f)
        recordUseCase("session-1", 1100L, 0.9f, 0.9f)
        recordUseCase("session-1", 1200L, 0.7f, 0.7f)

        val summary = makeFinishUseCase().invoke("session-1")

        assertEquals(3, summary.records.size)
        assertTrue(summary.records.all { it.sessionId == "session-1" })
    }

    @Test
    fun finishWorkout_usesDefaultSettingsWhenNoneExist() = runTest {
        insertUser()
        // Session with quality = 0.6f (in 0.5-0.8 range -> 1.0x multiplier with default settings)
        insertSession(id = "session-1", userId = "user-1", pushUpCount = 10, quality = 0.6f)
        // No settings saved -- should use defaults (pushUpsPerMinuteCredit=10, qualityMultiplierEnabled=true)

        val summary = makeFinishUseCase().invoke("session-1")

        // Default: 10 push-ups / 10 per min * 60 = 60 seconds, quality 0.6 -> 1.0x multiplier
        assertEquals(60L, summary.earnedCredits)
    }

    @Test
    fun finishWorkout_returnedSessionMatchesDatabase() = runTest {
        insertUser()
        insertSession(id = "session-1", userId = "user-1", pushUpCount = 10)
        settingsRepo.update(UserSettings.default("user-1"))

        val summary = makeFinishUseCase().invoke("session-1")

        // The returned session must match what is actually stored in the DB
        val stored = sessionRepo.getById("session-1")
        assertNotNull(stored)
        assertEquals(stored.endedAt, summary.session.endedAt)
        assertEquals(stored.earnedTimeCreditSeconds, summary.session.earnedTimeCreditSeconds)
        assertEquals(stored.syncStatus, summary.session.syncStatus)
    }

    // =========================================================================
    // Task 1A.11: GetTimeCreditUseCase
    // =========================================================================

    @Test
    fun getTimeCredit_returnsExistingCredit() = runTest {
        insertUser()
        timeCreditRepo.addEarnedSeconds("user-1", 300L)
        val useCase = GetTimeCreditUseCase(timeCreditRepo, fixedClock)

        val credit = useCase("user-1")

        assertEquals(300L, credit.totalEarnedSeconds)
        assertEquals(0L, credit.totalSpentSeconds)
        assertEquals(300L, credit.availableSeconds)
    }

    @Test
    fun getTimeCredit_createsEmptyCreditWhenNoneExists() = runTest {
        insertUser()
        val useCase = GetTimeCreditUseCase(timeCreditRepo, fixedClock)

        val credit = useCase("user-1")

        assertEquals(0L, credit.totalEarnedSeconds)
        assertEquals(0L, credit.totalSpentSeconds)
        assertEquals(0L, credit.availableSeconds)
    }

    @Test
    fun getTimeCredit_persistsEmptyCreditToDatabase() = runTest {
        insertUser()
        val useCase = GetTimeCreditUseCase(timeCreditRepo, fixedClock)

        useCase("user-1")

        val stored = timeCreditRepo.get("user-1")
        assertNotNull(stored)
        assertEquals(0L, stored.totalEarnedSeconds)
    }

    @Test
    fun getTimeCredit_calledTwice_returnsSameData() = runTest {
        insertUser()
        val useCase = GetTimeCreditUseCase(timeCreditRepo, fixedClock)

        val first = useCase("user-1")
        val second = useCase("user-1")

        assertEquals(first.totalEarnedSeconds, second.totalEarnedSeconds)
        assertEquals(first.totalSpentSeconds, second.totalSpentSeconds)
    }

    @Test
    fun getTimeCredit_requiresNonBlankUserId() = runTest {
        val useCase = GetTimeCreditUseCase(timeCreditRepo, fixedClock)

        assertFailsWith<IllegalArgumentException> {
            useCase("  ")
        }
    }

    @Test
    fun getTimeCredit_availableSecondsNeverNegative() = runTest {
        insertUser()
        val credit = TimeCredit(
            userId = "user-1",
            totalEarnedSeconds = 100L,
            totalSpentSeconds = 100L,
            lastUpdatedAt = fixedClock.now(),
            syncStatus = SyncStatus.PENDING,
        )
        timeCreditRepo.update(credit)
        val useCase = GetTimeCreditUseCase(timeCreditRepo, fixedClock)

        val result = useCase("user-1")

        assertEquals(0L, result.availableSeconds)
    }

    // =========================================================================
    // Task 1A.12: SpendTimeCreditUseCase
    // =========================================================================

    @Test
    fun spendTimeCredit_successfullyDeductsCredits() = runTest {
        insertUser()
        timeCreditRepo.addEarnedSeconds("user-1", 300L)
        val useCase = SpendTimeCreditUseCase(timeCreditRepo, fixedClock)

        val result = useCase("user-1", 100L)

        assertIs<SpendResult.Success>(result)
        assertEquals(200L, result.credit.availableSeconds)
        assertEquals(100L, result.credit.totalSpentSeconds)
    }

    @Test
    fun spendTimeCredit_returnsInsufficientCreditsWhenBalanceTooLow() = runTest {
        insertUser()
        timeCreditRepo.addEarnedSeconds("user-1", 50L)
        val useCase = SpendTimeCreditUseCase(timeCreditRepo, fixedClock)

        val result = useCase("user-1", 100L)

        assertIs<SpendResult.InsufficientCredits>(result)
        assertEquals(50L, result.credit.availableSeconds)
    }

    @Test
    fun spendTimeCredit_exactlyExhaustsBalance() = runTest {
        insertUser()
        timeCreditRepo.addEarnedSeconds("user-1", 100L)
        val useCase = SpendTimeCreditUseCase(timeCreditRepo, fixedClock)

        val result = useCase("user-1", 100L)

        assertIs<SpendResult.Success>(result)
        assertEquals(0L, result.credit.availableSeconds)
    }

    @Test
    fun spendTimeCredit_returnsInsufficientWhenNoCreditsExist() = runTest {
        insertUser()
        val useCase = SpendTimeCreditUseCase(timeCreditRepo, fixedClock)

        val result = useCase("user-1", 60L)

        assertIs<SpendResult.InsufficientCredits>(result)
        assertEquals(0L, result.credit.availableSeconds)
    }

    @Test
    fun spendTimeCredit_throwsForZeroSeconds() = runTest {
        val useCase = SpendTimeCreditUseCase(timeCreditRepo, fixedClock)

        assertFailsWith<IllegalArgumentException> {
            useCase("user-1", 0L)
        }
    }

    @Test
    fun spendTimeCredit_throwsForNegativeSeconds() = runTest {
        val useCase = SpendTimeCreditUseCase(timeCreditRepo, fixedClock)

        assertFailsWith<IllegalArgumentException> {
            useCase("user-1", -10L)
        }
    }

    @Test
    fun spendTimeCredit_throwsForBlankUserId() = runTest {
        val useCase = SpendTimeCreditUseCase(timeCreditRepo, fixedClock)

        assertFailsWith<IllegalArgumentException> {
            useCase("", 60L)
        }
    }

    @Test
    fun spendTimeCredit_persistsDeductionToDatabase() = runTest {
        insertUser()
        timeCreditRepo.addEarnedSeconds("user-1", 500L)
        val useCase = SpendTimeCreditUseCase(timeCreditRepo, fixedClock)

        useCase("user-1", 200L)

        val stored = timeCreditRepo.get("user-1")
        assertNotNull(stored)
        assertEquals(200L, stored.totalSpentSeconds)
        assertEquals(300L, stored.availableSeconds)
    }

    // =========================================================================
    // Task 1A.13: Stats Use-Cases
    // =========================================================================

    private suspend fun insertSessionWithData(
        id: String,
        userId: String = "user-1",
        startedAtMs: Long,
        pushUpCount: Int = 20,
        earnedSeconds: Long = 120L,
        quality: Float = 0.8f,
    ) {
        val session = WorkoutSession(
            id = id,
            userId = userId,
            startedAt = Instant.fromEpochMilliseconds(startedAtMs),
            endedAt = Instant.fromEpochMilliseconds(startedAtMs + 300_000L),
            pushUpCount = pushUpCount,
            earnedTimeCreditSeconds = earnedSeconds,
            quality = quality,
            syncStatus = SyncStatus.PENDING,
        )
        sessionRepo.save(session)
    }

    // --- GetDailyStatsUseCase ---

    @Test
    fun getDailyStats_returnsNullForEmptyDay() = runTest {
        insertUser()
        val useCase = GetDailyStatsUseCase(statsRepo)

        val result = useCase("user-1", LocalDate(2023, 11, 15))

        assertNull(result)
    }

    @Test
    fun getDailyStats_aggregatesSessionsForDay() = runTest {
        insertUser()
        // 2023-11-15T00:00:00Z = 1700006400000
        val dayStart = 1_700_006_400_000L
        insertSessionWithData("s1", startedAtMs = dayStart + 3600_000L, pushUpCount = 20, earnedSeconds = 120L)
        insertSessionWithData("s2", startedAtMs = dayStart + 7200_000L, pushUpCount = 30, earnedSeconds = 180L)
        val useCase = GetDailyStatsUseCase(statsRepo)

        val result = useCase("user-1", LocalDate(2023, 11, 15))

        assertNotNull(result)
        assertEquals(50, result.totalPushUps)
        assertEquals(2, result.totalSessions)
        assertEquals(300L, result.totalEarnedSeconds)
        // averagePushUpsPerSession: (20 + 30) / 2 = 25
        assertEquals(25f, result.averagePushUpsPerSession, 0.001f)
        // bestSession: max(20, 30) = 30
        assertEquals(30, result.bestSession)
    }

    @Test
    fun getDailyStats_requiresNonBlankUserId() = runTest {
        val useCase = GetDailyStatsUseCase(statsRepo)

        assertFailsWith<IllegalArgumentException> {
            useCase("", LocalDate(2023, 11, 15))
        }
    }

    // --- GetWeeklyStatsUseCase ---

    @Test
    fun getWeeklyStats_returnsNullForEmptyWeek() = runTest {
        insertUser()
        val useCase = GetWeeklyStatsUseCase(statsRepo)

        val result = useCase("user-1", LocalDate(2023, 11, 13))

        assertNull(result)
    }

    @Test
    fun getWeeklyStats_aggregatesAcrossDays() = runTest {
        insertUser()
        // Week of 2023-11-13 (Monday): 1699833600000
        val mondayStart = 1_699_833_600_000L
        val tuesdayStart = mondayStart + 86_400_000L
        insertSessionWithData("s1", startedAtMs = mondayStart + 3600_000L, pushUpCount = 20, earnedSeconds = 120L)
        insertSessionWithData("s2", startedAtMs = tuesdayStart + 3600_000L, pushUpCount = 30, earnedSeconds = 180L)
        val useCase = GetWeeklyStatsUseCase(statsRepo)

        val result = useCase("user-1", LocalDate(2023, 11, 13))

        assertNotNull(result)
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
    fun getWeeklyStats_requiresNonBlankUserId() = runTest {
        val useCase = GetWeeklyStatsUseCase(statsRepo)

        assertFailsWith<IllegalArgumentException> {
            useCase("", LocalDate(2023, 11, 13))
        }
    }

    // --- GetMonthlyStatsUseCase ---

    @Test
    fun getMonthlyStats_returnsNullForEmptyMonth() = runTest {
        insertUser()
        val useCase = GetMonthlyStatsUseCase(statsRepo)

        val result = useCase("user-1", 11, 2023)

        assertNull(result)
    }

    @Test
    fun getMonthlyStats_aggregatesAcrossWeeks() = runTest {
        insertUser()
        // Nov 1, 2023 = 1698796800000
        val nov1 = 1_698_796_800_000L
        val nov15 = nov1 + 14 * 86_400_000L
        insertSessionWithData("s1", startedAtMs = nov1 + 3600_000L, pushUpCount = 20, earnedSeconds = 120L)
        insertSessionWithData("s2", startedAtMs = nov15 + 3600_000L, pushUpCount = 30, earnedSeconds = 180L)
        val useCase = GetMonthlyStatsUseCase(statsRepo)

        val result = useCase("user-1", 11, 2023)

        assertNotNull(result)
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
    fun getMonthlyStats_throwsForInvalidMonth() = runTest {
        val useCase = GetMonthlyStatsUseCase(statsRepo)

        assertFailsWith<IllegalArgumentException> { useCase("user-1", 0, 2023) }
        assertFailsWith<IllegalArgumentException> { useCase("user-1", 13, 2023) }
    }

    @Test
    fun getMonthlyStats_throwsForInvalidYear() = runTest {
        val useCase = GetMonthlyStatsUseCase(statsRepo)

        assertFailsWith<IllegalArgumentException> { useCase("user-1", 6, 0) }
        assertFailsWith<IllegalArgumentException> { useCase("user-1", 6, -1) }
    }

    @Test
    fun getMonthlyStats_requiresNonBlankUserId() = runTest {
        val useCase = GetMonthlyStatsUseCase(statsRepo)

        assertFailsWith<IllegalArgumentException> {
            useCase("", 11, 2023)
        }
    }

    // --- GetTotalStatsUseCase ---

    @Test
    fun getTotalStats_returnsNullWhenNoData() = runTest {
        insertUser()
        val useCase = GetTotalStatsUseCase(statsRepo)

        val result = useCase("user-1")

        assertNull(result)
    }

    @Test
    fun getTotalStats_aggregatesAllSessions() = runTest {
        insertUser()
        val day1 = 1_700_006_400_000L // 2023-11-15T00:00:00Z
        val day2 = day1 + 86_400_000L  // 2023-11-16T00:00:00Z
        insertSessionWithData("s1", startedAtMs = day1 + 3600_000L, pushUpCount = 20, earnedSeconds = 120L, quality = 0.8f)
        insertSessionWithData("s2", startedAtMs = day2 + 3600_000L, pushUpCount = 30, earnedSeconds = 180L, quality = 0.9f)
        timeCreditRepo.addEarnedSeconds("user-1", 300L)
        timeCreditRepo.addSpentSeconds("user-1", 100L)
        // Set clock to 2023-11-16 so the last training day (2023-11-16) is "today"
        fixedClock.nowMs = day2 + 3600_000L
        val useCase = GetTotalStatsUseCase(statsRepo)

        val result = useCase("user-1")

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
        // Two consecutive days, last day is today -> streak of 2
        assertEquals(2, result.currentStreakDays)
        assertEquals(2, result.longestStreakDays)
    }

    @Test
    fun getTotalStats_calculatesStreakCorrectly() = runTest {
        insertUser()
        // 2023-11-15T00:00:00Z
        val baseDay = 1_700_006_400_000L
        val oneDay = 86_400_000L

        // Days 0, 1, 2 (consecutive), then gap, then days 4, 5
        // day 0 = 2023-11-15, day 5 = 2023-11-20
        for (i in 0 until 3) {
            insertSessionWithData(
                id = "s${i + 1}",
                startedAtMs = baseDay + i * oneDay + 3600_000L,
                pushUpCount = 10,
                earnedSeconds = 60L,
            )
        }
        for (i in 4 until 6) {
            insertSessionWithData(
                id = "s${i + 1}",
                startedAtMs = baseDay + i * oneDay + 3600_000L,
                pushUpCount = 10,
                earnedSeconds = 60L,
            )
        }
        // Set clock to day 5 (2023-11-20) so the last training day is "today"
        fixedClock.nowMs = baseDay + 5 * oneDay + 3600_000L
        val useCase = GetTotalStatsUseCase(statsRepo)

        val result = useCase("user-1")

        assertNotNull(result)
        // Current streak: days 4 and 5 = 2 (last day is today)
        assertEquals(2, result.currentStreakDays)
        // Longest streak: days 0, 1, 2 = 3
        assertEquals(3, result.longestStreakDays)
    }

    @Test
    fun getTotalStats_currentStreakIsZeroWhenLastWorkoutTooOld() = runTest {
        insertUser()
        val baseDay = 1_700_006_400_000L // 2023-11-15
        val oneDay = 86_400_000L
        // Session on day 0 (2023-11-15)
        insertSessionWithData("s1", startedAtMs = baseDay + 3600_000L, pushUpCount = 10, earnedSeconds = 60L)
        // Clock is set to day 3 (2023-11-18) -- two days after the last workout
        fixedClock.nowMs = baseDay + 3 * oneDay
        val useCase = GetTotalStatsUseCase(statsRepo)

        val result = useCase("user-1")

        assertNotNull(result)
        // Last workout was 2023-11-15, today is 2023-11-18 -> streak broken
        assertEquals(0, result.currentStreakDays)
        assertEquals(1, result.longestStreakDays)
    }

    @Test
    fun getTotalStats_currentStreakCountsWhenLastWorkoutWasYesterday() = runTest {
        insertUser()
        val baseDay = 1_700_006_400_000L // 2023-11-15
        val oneDay = 86_400_000L
        // Sessions on days 0 and 1 (2023-11-15, 2023-11-16)
        insertSessionWithData("s1", startedAtMs = baseDay + 3600_000L, pushUpCount = 10, earnedSeconds = 60L)
        insertSessionWithData("s2", startedAtMs = baseDay + oneDay + 3600_000L, pushUpCount = 10, earnedSeconds = 60L)
        // Clock is set to day 2 (2023-11-17) -- yesterday was the last workout
        fixedClock.nowMs = baseDay + 2 * oneDay
        val useCase = GetTotalStatsUseCase(statsRepo)

        val result = useCase("user-1")

        assertNotNull(result)
        // Last workout was yesterday -> streak still active
        assertEquals(2, result.currentStreakDays)
        assertEquals(2, result.longestStreakDays)
    }

    @Test
    fun getTotalStats_requiresNonBlankUserId() = runTest {
        val useCase = GetTotalStatsUseCase(statsRepo)

        assertFailsWith<IllegalArgumentException> {
            useCase("")
        }
    }

    // =========================================================================
    // IdGenerator tests
    // =========================================================================

    @Test
    fun defaultIdGenerator_producesUniqueIds() {
        val ids = (1..100).map { DefaultIdGenerator.generate() }.toSet()
        assertEquals(100, ids.size)
    }

    @Test
    fun defaultIdGenerator_producesValidUuidFormat() {
        val id = DefaultIdGenerator.generate()
        // UUID v4 format: 8-4-4-4-12 hex chars separated by dashes
        val uuidRegex = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        assertTrue(uuidRegex.matches(id), "Expected UUID v4 format but got: $id")
    }

    @Test
    fun defaultIdGenerator_versionNibbleIsAlways4() {
        repeat(50) {
            val id = DefaultIdGenerator.generate()
            // The version nibble is at position 14 (after "xxxxxxxx-xxxx-")
            assertEquals('4', id[14], "Version nibble should be '4' in: $id")
        }
    }

    @Test
    fun defaultIdGenerator_variantNibbleIsAlwaysRfc4122() {
        repeat(50) {
            val id = DefaultIdGenerator.generate()
            // The variant nibble is at position 19 (after "xxxxxxxx-xxxx-4xxx-")
            val variantChar = id[19]
            assertTrue(
                variantChar in setOf('8', '9', 'a', 'b'),
                "Variant nibble should be 8, 9, a, or b but got '$variantChar' in: $id",
            )
        }
    }
}
