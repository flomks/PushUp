package com.pushup.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToOneOrNull
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.UpdateTimeCreditRequest
import com.pushup.data.mapper.syncStatusToString
import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.SyncStatus
import com.pushup.domain.model.TimeCredit
import com.pushup.domain.repository.TimeCreditRepository
import com.pushup.domain.usecase.sync.NetworkMonitor
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock

/**
 * SQLDelight-backed implementation of [TimeCreditRepository] with optional
 * cloud-sync support.
 *
 * ## Offline-First / Cache Strategy
 * The local SQLite database is the **source of truth**. The cloud (Supabase) is
 * a backup and sync target:
 *
 * - Every mutation ([update], [addEarnedSeconds], [addSpentSeconds]) marks the
 *   local record as [SyncStatus.PENDING] and fires a background coroutine to
 *   push the change to Supabase. The caller is never blocked by the network.
 *
 * - On [get], the local record is returned immediately. If the cloud has a
 *   newer record (e.g. after login on a new device), [SyncFromCloudUseCase]
 *   will pull it down and [update] will be called with [SyncStatus.SYNCED].
 *
 * ## Cloud sync is optional
 * [cloudSyncApi] and [networkMonitor] are nullable. When either is `null` the
 * repository behaves exactly like the original local-only implementation.
 *
 * ## Background sync scope
 * Background sync jobs are launched in [syncScope]. The default scope uses a
 * [SupervisorJob] so that individual sync failures do not cancel the scope.
 * Override [syncScope] in tests to control coroutine execution.
 *
 * All read-modify-write operations are wrapped in a [database.transaction]
 * to prevent lost-update anomalies.
 *
 * All suspend functions are main-safe -- dispatcher switching is handled
 * by [safeDbCall].
 */
class TimeCreditRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
    private val clock: Clock = Clock.System,
    private val cloudSyncApi: CloudSyncApi? = null,
    private val networkMonitor: NetworkMonitor? = null,
    private val syncScope: CoroutineScope = CoroutineScope(SupervisorJob()),
) : TimeCreditRepository {

    private val queries get() = database.databaseQueries

    override suspend fun get(userId: String): TimeCredit? = safeDbCall(
        dispatcher,
        "Failed to get time credit for user '$userId'",
    ) {
        queries.selectTimeCreditByUserId(userId).executeAsOneOrNull()?.toDomain()
    }

    /**
     * Replaces the entire time-credit record and triggers a background sync.
     *
     * If [credit] has [SyncStatus.SYNCED] (e.g. it was pulled from the cloud),
     * no background upload is triggered.
     */
    override suspend fun update(credit: TimeCredit): Unit = safeDbCall(
        dispatcher,
        "Failed to update time credit for user '${credit.userId}'",
    ) {
        database.transaction {
            val existingRow = queries.selectTimeCreditByUserId(credit.userId).executeAsOneOrNull()
            val rowId = existingRow?.id ?: credit.userId
            queries.upsertTimeCredit(
                id = rowId,
                userId = credit.userId,
                totalEarnedSeconds = credit.totalEarnedSeconds,
                totalSpentSeconds = credit.totalSpentSeconds,
                lastUpdatedAt = credit.lastUpdatedAt.toEpochMilliseconds(),
                syncStatus = syncStatusToString(credit.syncStatus),
            )
        }
        // Trigger background sync only for locally-mutated records.
        if (credit.syncStatus != SyncStatus.SYNCED) {
            triggerBackgroundSync(credit.userId, credit.totalEarnedSeconds, credit.totalSpentSeconds)
        }
    }

    /**
     * Atomically adds earned seconds and triggers a background sync.
     */
    override suspend fun addEarnedSeconds(userId: String, seconds: Long): Unit {
        require(seconds > 0) { "seconds must be > 0, was $seconds" }
        safeDbCall(
            dispatcher,
            "Failed to add $seconds earned seconds for user '$userId'",
        ) {
            val now = clock.now().toEpochMilliseconds()
            database.transaction {
                val existing = queries.selectTimeCreditByUserId(userId).executeAsOneOrNull()
                if (existing != null) {
                    queries.updateTimeCredit(
                        totalEarnedSeconds = existing.totalEarnedSeconds + seconds,
                        totalSpentSeconds = existing.totalSpentSeconds,
                        lastUpdatedAt = now,
                        syncStatus = syncStatusToString(SyncStatus.PENDING),
                        id = existing.id,
                    )
                } else {
                    queries.insertTimeCredit(
                        id = userId,
                        userId = userId,
                        totalEarnedSeconds = seconds,
                        totalSpentSeconds = 0,
                        lastUpdatedAt = now,
                        syncStatus = syncStatusToString(SyncStatus.PENDING),
                    )
                }
            }
        }
        // Trigger background sync after the local mutation.
        val updated = safeDbCall(dispatcher, "") {
            queries.selectTimeCreditByUserId(userId).executeAsOneOrNull()?.toDomain()
        }
        if (updated != null) {
            triggerBackgroundSync(userId, updated.totalEarnedSeconds, updated.totalSpentSeconds)
        }
    }

    /**
     * Atomically adds spent seconds and triggers a background sync.
     */
    override suspend fun addSpentSeconds(userId: String, seconds: Long): Unit {
        require(seconds > 0) { "seconds must be > 0, was $seconds" }
        safeDbCall(
            dispatcher,
            "Failed to add $seconds spent seconds for user '$userId'",
        ) {
            val now = clock.now().toEpochMilliseconds()
            database.transaction {
                val existing = queries.selectTimeCreditByUserId(userId).executeAsOneOrNull()
                if (existing != null) {
                    queries.updateTimeCredit(
                        totalEarnedSeconds = existing.totalEarnedSeconds,
                        totalSpentSeconds = existing.totalSpentSeconds + seconds,
                        lastUpdatedAt = now,
                        syncStatus = syncStatusToString(SyncStatus.PENDING),
                        id = existing.id,
                    )
                } else {
                    queries.insertTimeCredit(
                        id = userId,
                        userId = userId,
                        totalEarnedSeconds = 0,
                        totalSpentSeconds = seconds,
                        lastUpdatedAt = now,
                        syncStatus = syncStatusToString(SyncStatus.PENDING),
                    )
                }
            }
        }
        // Trigger background sync after the local mutation.
        val updated = safeDbCall(dispatcher, "") {
            queries.selectTimeCreditByUserId(userId).executeAsOneOrNull()?.toDomain()
        }
        if (updated != null) {
            triggerBackgroundSync(userId, updated.totalEarnedSeconds, updated.totalSpentSeconds)
        }
    }

    override suspend fun markAsSynced(userId: String): Unit = safeDbCall(
        dispatcher,
        "Failed to mark time credit as synced for user '$userId'",
    ) {
        database.transaction {
            val existing = queries.selectTimeCreditByUserId(userId).executeAsOneOrNull()
                ?: return@transaction
            queries.updateTimeCredit(
                totalEarnedSeconds = existing.totalEarnedSeconds,
                totalSpentSeconds = existing.totalSpentSeconds,
                lastUpdatedAt = clock.now().toEpochMilliseconds(),
                syncStatus = syncStatusToString(SyncStatus.SYNCED),
                id = existing.id,
            )
        }
    }

    override fun observeCredit(userId: String): Flow<TimeCredit?> =
        queries.selectTimeCreditByUserId(userId)
            .asFlow()
            .mapToOneOrNull(dispatcher)
            .map { it?.toDomain() }
            .catch { e ->
                throw RepositoryException("Failed to observe credit for user '$userId'", e)
            }

    // =========================================================================
    // Private cloud-sync helpers
    // =========================================================================

    /**
     * Launches a fire-and-forget coroutine that pushes the current credit
     * balance for [userId] to Supabase.
     *
     * Failures are silently swallowed -- the record remains [SyncStatus.PENDING]
     * in the local DB and will be retried by [SyncTimeCreditUseCase] on the
     * next sync cycle.
     */
    private fun triggerBackgroundSync(
        userId: String,
        totalEarnedSeconds: Long,
        totalSpentSeconds: Long,
    ) {
        val api = cloudSyncApi ?: return
        val monitor = networkMonitor ?: return

        syncScope.launch {
            try {
                if (!monitor.isConnected()) return@launch
                api.updateTimeCredit(
                    userId = userId,
                    request = UpdateTimeCreditRequest(
                        totalEarnedSeconds = totalEarnedSeconds,
                        totalSpentSeconds = totalSpentSeconds,
                    ),
                )
                // Mark as synced in the local DB.
                safeDbCall(dispatcher, "Failed to mark time credit as synced after background sync") {
                    database.transaction {
                        val existing = queries.selectTimeCreditByUserId(userId).executeAsOneOrNull()
                            ?: return@transaction
                        queries.updateTimeCredit(
                            totalEarnedSeconds = existing.totalEarnedSeconds,
                            totalSpentSeconds = existing.totalSpentSeconds,
                            lastUpdatedAt = clock.now().toEpochMilliseconds(),
                            syncStatus = syncStatusToString(SyncStatus.SYNCED),
                            id = existing.id,
                        )
                    }
                }
            } catch (_: Exception) {
                // Best-effort: failures are retried by SyncTimeCreditUseCase.
            }
        }
    }
}
