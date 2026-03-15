package com.pushup.data.mapper

import com.pushup.domain.model.PushUpRecord
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.model.User
import com.pushup.domain.model.UserSettings
import com.pushup.domain.model.WorkoutSession
import kotlinx.datetime.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import com.pushup.db.PushUpRecord as DbPushUpRecord
import com.pushup.db.TimeCredit as DbTimeCredit
import com.pushup.db.User as DbUser
import com.pushup.db.UserSettings as DbUserSettings
import com.pushup.db.WorkoutSession as DbWorkoutSession

class MapperTest {

    // =========================================================================
    // User mapper tests
    // =========================================================================

    @Test
    fun dbUser_toDomain_convertsAllFields() {
        val dbUser = DbUser(
            id = "user-123",
            email = "test@example.com",
            username = "test_user",
            displayName = "Test User",
            createdAt = 1_700_000_000_000L,
            syncedAt = 1_700_001_000_000L,
        )

        val domain = dbUser.toDomain()

        assertEquals("user-123", domain.id)
        assertEquals("test@example.com", domain.email)
        assertEquals("Test User", domain.displayName)
        assertEquals(Instant.fromEpochMilliseconds(1_700_000_000_000L), domain.createdAt)
        assertEquals(Instant.fromEpochMilliseconds(1_700_001_000_000L), domain.lastSyncedAt)
    }

    @Test
    fun dbUser_toDomain_nullSyncedAt_defaultsToCreatedAt() {
        val dbUser = DbUser(
            id = "user-456",
            email = "null@example.com",
            username = null,
            displayName = "Null Sync",
            createdAt = 1_700_000_000_000L,
            syncedAt = null,
        )

        val domain = dbUser.toDomain()

        assertEquals(domain.createdAt, domain.lastSyncedAt)
    }

    @Test
    fun user_toDbEntity_convertsAllFields() {
        val user = User(
            id = "user-789",
            email = "db@example.com",
            displayName = "DB User",
            createdAt = Instant.fromEpochMilliseconds(1_700_000_000_000L),
            lastSyncedAt = Instant.fromEpochMilliseconds(1_700_002_000_000L),
        )

        val db = user.toDbEntity()

        assertEquals("user-789", db.id)
        assertEquals("db@example.com", db.email)
        assertEquals("DB User", db.displayName)
        assertEquals(1_700_000_000_000L, db.createdAt)
        assertEquals(1_700_002_000_000L, db.syncedAt)
    }

    @Test
    fun user_roundTrip_preservesData() {
        val original = User(
            id = "round-trip-user",
            email = "round@trip.com",
            displayName = "Round Trip",
            createdAt = Instant.fromEpochMilliseconds(1_700_000_000_000L),
            lastSyncedAt = Instant.fromEpochMilliseconds(1_700_005_000_000L),
        )

        val roundTripped = original.toDbEntity().toDomain()

        assertEquals(original, roundTripped)
    }

    // =========================================================================
    // WorkoutSession mapper tests
    // =========================================================================

    @Test
    fun dbWorkoutSession_toDomain_convertsAllFields() {
        val dbSession = DbWorkoutSession(
            id = "session-1",
            userId = "user-1",
            startedAt = 1_700_000_000_000L,
            endedAt = 1_700_000_300_000L,
            pushUpCount = 25L,
            earnedTimeCredits = 150L,
            quality = 0.85,
            syncStatus = "synced",
            updatedAt = 1_700_000_400_000L,
        )

        val domain = dbSession.toDomain()

        assertEquals("session-1", domain.id)
        assertEquals("user-1", domain.userId)
        assertEquals(Instant.fromEpochMilliseconds(1_700_000_000_000L), domain.startedAt)
        assertEquals(Instant.fromEpochMilliseconds(1_700_000_300_000L), domain.endedAt)
        assertEquals(25, domain.pushUpCount)
        assertEquals(150L, domain.earnedTimeCreditSeconds)
        assertEquals(0.85f, domain.quality)
        assertEquals(SyncStatus.SYNCED, domain.syncStatus)
    }

    @Test
    fun dbWorkoutSession_toDomain_nullEndedAt() {
        val dbSession = DbWorkoutSession(
            id = "session-active",
            userId = "user-1",
            startedAt = 1_700_000_000_000L,
            endedAt = null,
            pushUpCount = 10L,
            earnedTimeCredits = 0L,
            quality = 0.5,
            syncStatus = "pending",
            updatedAt = 1_700_000_100_000L,
        )

        val domain = dbSession.toDomain()

        assertNull(domain.endedAt)
        assertTrue(domain.isActive)
        assertEquals(SyncStatus.PENDING, domain.syncStatus)
    }

    @Test
    fun workoutSession_toDbEntity_convertsAllFields() {
        val updatedAt = Instant.fromEpochMilliseconds(1_700_000_500_000L)
        val session = WorkoutSession(
            id = "session-2",
            userId = "user-2",
            startedAt = Instant.fromEpochMilliseconds(1_700_000_000_000L),
            endedAt = Instant.fromEpochMilliseconds(1_700_000_300_000L),
            pushUpCount = 30,
            earnedTimeCreditSeconds = 180L,
            quality = 0.9f,
            syncStatus = SyncStatus.FAILED,
        )

        val db = session.toDbEntity(updatedAt = updatedAt)

        assertEquals("session-2", db.id)
        assertEquals("user-2", db.userId)
        assertEquals(1_700_000_000_000L, db.startedAt)
        assertEquals(1_700_000_300_000L, db.endedAt)
        assertEquals(30L, db.pushUpCount)
        assertEquals(180L, db.earnedTimeCredits)
        assertEquals(0.9, db.quality, 0.001)
        assertEquals("failed", db.syncStatus)
        assertEquals(1_700_000_500_000L, db.updatedAt)
    }

    @Test
    fun workoutSession_toDbEntity_nullEndedAt() {
        val session = WorkoutSession(
            id = "session-null-end",
            userId = "user-1",
            startedAt = Instant.fromEpochMilliseconds(1_700_000_000_000L),
            endedAt = null,
            pushUpCount = 0,
            earnedTimeCreditSeconds = 0L,
            quality = 0.0f,
            syncStatus = SyncStatus.PENDING,
        )

        val db = session.toDbEntity(updatedAt = Instant.fromEpochMilliseconds(1L))

        assertNull(db.endedAt)
    }

    @Test
    fun workoutSession_toDbEntity_requiresExplicitUpdatedAt() {
        val session = WorkoutSession(
            id = "session-explicit",
            userId = "user-1",
            startedAt = Instant.fromEpochMilliseconds(1_700_000_000_000L),
            endedAt = null,
            pushUpCount = 5,
            earnedTimeCreditSeconds = 30L,
            quality = 0.5f,
            syncStatus = SyncStatus.PENDING,
        )

        val explicitTimestamp = Instant.fromEpochMilliseconds(1_700_099_000_000L)
        val db = session.toDbEntity(updatedAt = explicitTimestamp)

        assertEquals(1_700_099_000_000L, db.updatedAt)
    }

    @Test
    fun workoutSession_roundTrip_preservesCoreFields() {
        val original = WorkoutSession(
            id = "round-trip-session",
            userId = "user-rt",
            startedAt = Instant.fromEpochMilliseconds(1_700_000_000_000L),
            endedAt = Instant.fromEpochMilliseconds(1_700_000_600_000L),
            pushUpCount = 50,
            earnedTimeCreditSeconds = 300L,
            quality = 0.75f,
            syncStatus = SyncStatus.SYNCED,
        )

        val roundTripped = original.toDbEntity(
            updatedAt = Instant.fromEpochMilliseconds(1_700_000_700_000L),
        ).toDomain()

        assertEquals(original.id, roundTripped.id)
        assertEquals(original.userId, roundTripped.userId)
        assertEquals(original.startedAt, roundTripped.startedAt)
        assertEquals(original.endedAt, roundTripped.endedAt)
        assertEquals(original.pushUpCount, roundTripped.pushUpCount)
        assertEquals(original.earnedTimeCreditSeconds, roundTripped.earnedTimeCreditSeconds)
        assertEquals(original.quality, roundTripped.quality, 0.001f)
        assertEquals(original.syncStatus, roundTripped.syncStatus)
    }

    // =========================================================================
    // PushUpRecord mapper tests
    // =========================================================================

    @Test
    fun dbPushUpRecord_toDomain_convertsAllFields() {
        val dbRecord = DbPushUpRecord(
            id = "record-1",
            sessionId = "session-1",
            timestamp = 1_700_000_050_000L,
            durationMs = 1200L,
            depthScore = 0.9,
            formScore = 0.85,
        )

        val domain = dbRecord.toDomain()

        assertEquals("record-1", domain.id)
        assertEquals("session-1", domain.sessionId)
        assertEquals(Instant.fromEpochMilliseconds(1_700_000_050_000L), domain.timestamp)
        assertEquals(1200L, domain.durationMs)
        assertEquals(0.9f, domain.depthScore, 0.001f)
        assertEquals(0.85f, domain.formScore, 0.001f)
    }

    @Test
    fun pushUpRecord_toDbEntity_convertsAllFields() {
        val record = PushUpRecord(
            id = "record-2",
            sessionId = "session-2",
            timestamp = Instant.fromEpochMilliseconds(1_700_000_100_000L),
            durationMs = 800L,
            depthScore = 0.7f,
            formScore = 0.65f,
        )

        val db = record.toDbEntity()

        assertEquals("record-2", db.id)
        assertEquals("session-2", db.sessionId)
        assertEquals(1_700_000_100_000L, db.timestamp)
        assertEquals(800L, db.durationMs)
        assertEquals(0.7, db.depthScore, 0.001)
        assertEquals(0.65, db.formScore, 0.001)
    }

    @Test
    fun pushUpRecord_roundTrip_preservesData() {
        val original = PushUpRecord(
            id = "round-trip-record",
            sessionId = "session-rt",
            timestamp = Instant.fromEpochMilliseconds(1_700_000_200_000L),
            durationMs = 950L,
            depthScore = 0.8f,
            formScore = 0.75f,
        )

        val roundTripped = original.toDbEntity().toDomain()

        assertEquals(original.id, roundTripped.id)
        assertEquals(original.sessionId, roundTripped.sessionId)
        assertEquals(original.timestamp, roundTripped.timestamp)
        assertEquals(original.durationMs, roundTripped.durationMs)
        assertEquals(original.depthScore, roundTripped.depthScore, 0.001f)
        assertEquals(original.formScore, roundTripped.formScore, 0.001f)
    }

    // =========================================================================
    // TimeCredit mapper tests
    // =========================================================================

    @Test
    fun dbTimeCredit_toDomain_convertsAllFields() {
        val dbCredit = DbTimeCredit(
            id = "credit-1",
            userId = "user-1",
            totalEarnedSeconds = 3600L,
            totalSpentSeconds = 1800L,
            lastUpdatedAt = 1_700_000_000_000L,
            syncStatus = "synced",
        )

        val domain = dbCredit.toDomain()

        assertEquals("user-1", domain.userId)
        assertEquals(3600L, domain.totalEarnedSeconds)
        assertEquals(1800L, domain.totalSpentSeconds)
        assertEquals(Instant.fromEpochMilliseconds(1_700_000_000_000L), domain.lastUpdatedAt)
        assertEquals(SyncStatus.SYNCED, domain.syncStatus)
        assertEquals(1800L, domain.availableSeconds)
        assertTrue(domain.hasCredits)
    }

    @Test
    fun timeCredit_toDbEntity_convertsAllFields() {
        val credit = TimeCredit(
            userId = "user-2",
            totalEarnedSeconds = 7200L,
            totalSpentSeconds = 7200L,
            lastUpdatedAt = Instant.fromEpochMilliseconds(1_700_001_000_000L),
            syncStatus = SyncStatus.PENDING,
        )

        val db = credit.toDbEntity(id = "credit-2")

        assertEquals("credit-2", db.id)
        assertEquals("user-2", db.userId)
        assertEquals(7200L, db.totalEarnedSeconds)
        assertEquals(7200L, db.totalSpentSeconds)
        assertEquals(1_700_001_000_000L, db.lastUpdatedAt)
        assertEquals("pending", db.syncStatus)
    }

    @Test
    fun timeCredit_roundTrip_preservesCoreFields() {
        val original = TimeCredit(
            userId = "user-rt",
            totalEarnedSeconds = 5000L,
            totalSpentSeconds = 2500L,
            lastUpdatedAt = Instant.fromEpochMilliseconds(1_700_002_000_000L),
            syncStatus = SyncStatus.FAILED,
        )

        val roundTripped = original.toDbEntity(id = "credit-rt").toDomain()

        assertEquals(original.userId, roundTripped.userId)
        assertEquals(original.totalEarnedSeconds, roundTripped.totalEarnedSeconds)
        assertEquals(original.totalSpentSeconds, roundTripped.totalSpentSeconds)
        assertEquals(original.lastUpdatedAt, roundTripped.lastUpdatedAt)
        assertEquals(original.syncStatus, roundTripped.syncStatus)
    }

    @Test
    fun timeCredit_zeroCreditBalance() {
        val dbCredit = DbTimeCredit(
            id = "credit-zero",
            userId = "user-zero",
            totalEarnedSeconds = 0L,
            totalSpentSeconds = 0L,
            lastUpdatedAt = 1_700_000_000_000L,
            syncStatus = "pending",
        )

        val domain = dbCredit.toDomain()

        assertEquals(0L, domain.availableSeconds)
        assertFalse(domain.hasCredits)
    }

    // =========================================================================
    // UserSettings mapper tests
    // =========================================================================

    @Test
    fun dbUserSettings_toDomain_convertsAllFields() {
        val dbSettings = DbUserSettings(
            id = "settings-1",
            userId = "user-1",
            pushUpsPerMinuteCredit = 15L,
            qualityMultiplierEnabled = 1L,
            dailyCreditCapSeconds = 3600L,
            searchableByEmail = 1L,
        )

        val domain = dbSettings.toDomain()

        assertEquals("user-1", domain.userId)
        assertEquals(15, domain.pushUpsPerMinuteCredit)
        assertTrue(domain.qualityMultiplierEnabled)
        assertEquals(3600L, domain.dailyCreditCapSeconds)
        assertTrue(domain.searchableByEmail)
    }

    @Test
    fun dbUserSettings_toDomain_qualityMultiplierDisabled() {
        val dbSettings = DbUserSettings(
            id = "settings-2",
            userId = "user-2",
            pushUpsPerMinuteCredit = 10L,
            qualityMultiplierEnabled = 0L,
            dailyCreditCapSeconds = null,
            searchableByEmail = 0L,
        )

        val domain = dbSettings.toDomain()

        assertFalse(domain.qualityMultiplierEnabled)
        assertNull(domain.dailyCreditCapSeconds)
        assertFalse(domain.searchableByEmail)
    }

    @Test
    fun userSettings_toDbEntity_convertsAllFields() {
        val settings = UserSettings(
            userId = "user-3",
            pushUpsPerMinuteCredit = 20,
            qualityMultiplierEnabled = true,
            dailyCreditCapSeconds = 7200L,
            searchableByEmail = true,
        )

        val db = settings.toDbEntity(id = "settings-3")

        assertEquals("settings-3", db.id)
        assertEquals("user-3", db.userId)
        assertEquals(20L, db.pushUpsPerMinuteCredit)
        assertEquals(1L, db.qualityMultiplierEnabled)
        assertEquals(7200L, db.dailyCreditCapSeconds)
        assertEquals(1L, db.searchableByEmail)
    }

    @Test
    fun userSettings_toDbEntity_disabledMultiplier_nullCap() {
        val settings = UserSettings(
            userId = "user-4",
            pushUpsPerMinuteCredit = 5,
            qualityMultiplierEnabled = false,
            dailyCreditCapSeconds = null,
            searchableByEmail = false,
        )

        val db = settings.toDbEntity(id = "settings-4")

        assertEquals(0L, db.qualityMultiplierEnabled)
        assertNull(db.dailyCreditCapSeconds)
        assertEquals(0L, db.searchableByEmail)
    }

    @Test
    fun userSettings_roundTrip_preservesCoreFields() {
        val original = UserSettings(
            userId = "user-rt",
            pushUpsPerMinuteCredit = 12,
            qualityMultiplierEnabled = true,
            dailyCreditCapSeconds = 1800L,
            searchableByEmail = true,
        )

        val roundTripped = original.toDbEntity(id = "settings-rt").toDomain()

        assertEquals(original.userId, roundTripped.userId)
        assertEquals(original.pushUpsPerMinuteCredit, roundTripped.pushUpsPerMinuteCredit)
        assertEquals(original.qualityMultiplierEnabled, roundTripped.qualityMultiplierEnabled)
        assertEquals(original.dailyCreditCapSeconds, roundTripped.dailyCreditCapSeconds)
        assertEquals(original.searchableByEmail, roundTripped.searchableByEmail)
    }

    // =========================================================================
    // SyncStatus conversion tests
    // =========================================================================

    @Test
    fun syncStatusFromString_allKnownValues() {
        assertEquals(SyncStatus.SYNCED, syncStatusFromString("synced"))
        assertEquals(SyncStatus.PENDING, syncStatusFromString("pending"))
        assertEquals(SyncStatus.FAILED, syncStatusFromString("failed"))
    }

    @Test
    fun syncStatusFromString_syncingMapsToSynced_designChoice() {
        // The DB schema defines "syncing" as a transient state. The domain
        // layer deliberately re-queues these as PENDING on restart.
        assertEquals(SyncStatus.PENDING, syncStatusFromString("syncing"))
    }

    @Test
    fun syncStatusFromString_unknownValue_defaultsToPending() {
        assertEquals(SyncStatus.PENDING, syncStatusFromString("unknown"))
        assertEquals(SyncStatus.PENDING, syncStatusFromString(""))
    }

    @Test
    fun syncStatusToString_allValues() {
        assertEquals("synced", syncStatusToString(SyncStatus.SYNCED))
        assertEquals("pending", syncStatusToString(SyncStatus.PENDING))
        assertEquals("failed", syncStatusToString(SyncStatus.FAILED))
    }

    @Test
    fun syncStatus_roundTrip_allValues() {
        SyncStatus.entries.forEach { status ->
            val roundTripped = syncStatusFromString(syncStatusToString(status))
            assertEquals(status, roundTripped)
        }
    }

    // =========================================================================
    // Numeric overflow guard tests
    // =========================================================================

    @Test
    fun toIntChecked_validRange_converts() {
        assertEquals(0, 0L.toIntChecked("test"))
        assertEquals(Int.MAX_VALUE, Int.MAX_VALUE.toLong().toIntChecked("test"))
        assertEquals(Int.MIN_VALUE, Int.MIN_VALUE.toLong().toIntChecked("test"))
        assertEquals(42, 42L.toIntChecked("test"))
        assertEquals(-1, (-1L).toIntChecked("test"))
    }

    @Test
    fun toIntChecked_overflow_throws() {
        assertFailsWith<IllegalStateException> {
            (Int.MAX_VALUE.toLong() + 1).toIntChecked("pushUpCount")
        }
    }

    @Test
    fun toIntChecked_underflow_throws() {
        assertFailsWith<IllegalStateException> {
            (Int.MIN_VALUE.toLong() - 1).toIntChecked("pushUpCount")
        }
    }

    // =========================================================================
    // Timestamp conversion edge cases
    // =========================================================================

    @Test
    fun timestamp_epochZero_convertsCorrectly() {
        val dbUser = DbUser(
            id = "epoch-user",
            email = "epoch@example.com",
            username = null,
            displayName = "Epoch User",
            createdAt = 0L,
            syncedAt = 0L,
        )

        val domain = dbUser.toDomain()

        assertEquals(Instant.fromEpochMilliseconds(0L), domain.createdAt)
        assertEquals(Instant.fromEpochMilliseconds(0L), domain.lastSyncedAt)
    }

    @Test
    fun timestamp_largeValue_convertsCorrectly() {
        // A date far in the future (year ~2100)
        val farFuture = 4_102_444_800_000L
        val dbUser = DbUser(
            id = "future-user",
            email = "future@example.com",
            username = null,
            displayName = "Future User",
            createdAt = farFuture,
            syncedAt = farFuture,
        )

        val domain = dbUser.toDomain()

        assertEquals(Instant.fromEpochMilliseconds(farFuture), domain.createdAt)
        assertEquals(farFuture, domain.toDbEntity().createdAt)
    }

    // =========================================================================
    // Boolean mapping edge cases
    // =========================================================================

    @Test
    fun booleanMapping_nonStandardTruthyValues_treatedAsTrue() {
        // SQLite convention: any non-zero integer is truthy
        val dbSettings = DbUserSettings(
            id = "settings-truthy",
            userId = "user-truthy",
            pushUpsPerMinuteCredit = 10L,
            qualityMultiplierEnabled = 42L,
            dailyCreditCapSeconds = null,
            searchableByEmail = 0L,
        )

        val domain = dbSettings.toDomain()

        assertTrue(domain.qualityMultiplierEnabled)
    }

    @Test
    fun booleanMapping_negativeValue_treatedAsTrue() {
        val dbSettings = DbUserSettings(
            id = "settings-neg",
            userId = "user-neg",
            pushUpsPerMinuteCredit = 10L,
            qualityMultiplierEnabled = -1L,
            dailyCreditCapSeconds = null,
            searchableByEmail = 0L,
        )

        val domain = dbSettings.toDomain()

        assertTrue(domain.qualityMultiplierEnabled)
    }

    // =========================================================================
    // List mapper convenience tests
    // =========================================================================

    @Test
    fun list_dbUsers_toDomain_mapsAll() {
        val dbUsers = listOf(
            DbUser("u1", "a@b.com", null, "A", 1_000L, 2_000L),
            DbUser("u2", "c@d.com", null, "B", 3_000L, null),
        )

        val domainUsers = dbUsers.map { it.toDomain() }

        assertEquals(2, domainUsers.size)
        assertEquals("u1", domainUsers[0].id)
        assertEquals("u2", domainUsers[1].id)
        // Second user: syncedAt null -> falls back to createdAt
        assertEquals(domainUsers[1].createdAt, domainUsers[1].lastSyncedAt)
    }

    @Test
    fun list_dbPushUpRecords_toDomain_mapsAll() {
        val dbRecords = listOf(
            DbPushUpRecord("r1", "s1", 1_000L, 500L, 0.8, 0.7),
            DbPushUpRecord("r2", "s1", 2_000L, 600L, 0.9, 0.85),
            DbPushUpRecord("r3", "s1", 3_000L, 700L, 1.0, 1.0),
        )

        val domainRecords = dbRecords.map { it.toDomain() }

        assertEquals(3, domainRecords.size)
        assertEquals("r1", domainRecords[0].id)
        assertEquals("r3", domainRecords[2].id)
        assertEquals(0.8f, domainRecords[0].depthScore, 0.001f)
        assertEquals(1.0f, domainRecords[2].formScore, 0.001f)
    }
}
