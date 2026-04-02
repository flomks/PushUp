package com.pushup.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.UpsertLiveRunPresenceRequest
import com.pushup.data.api.dto.toDomain
import com.pushup.db.LiveRunPresence as DbLiveRunPresence
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.LiveRunPresence
import com.pushup.domain.model.RunPresenceState
import com.pushup.domain.repository.LiveRunPresenceRepository
import com.pushup.domain.usecase.sync.NetworkMonitor
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.datetime.Instant

class LiveRunPresenceRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
    private val cloudSyncApi: CloudSyncApi? = null,
    private val networkMonitor: NetworkMonitor? = null,
) : LiveRunPresenceRepository {

    private val queries get() = database.databaseQueries

    override suspend fun upsert(presence: LiveRunPresence): LiveRunPresence = safeDbCall(
        dispatcher,
        "Failed to upsert live run presence '${presence.id}'",
    ) {
        upsertLocal(presence)
        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.upsertLiveRunPresence(
                UpsertLiveRunPresenceRequest(
                    id = presence.id,
                    sessionId = presence.sessionId,
                    userId = presence.userId,
                    presenceState = presence.state.toDbValue(),
                    lastSeenAt = presence.lastSeenAt.toString(),
                    currentDistanceMeters = presence.currentDistanceMeters,
                    currentDurationSeconds = presence.currentDurationSeconds.toInt(),
                    currentPaceSecondsPerKm = presence.currentPaceSecondsPerKm,
                    currentLatitude = presence.currentLatitude,
                    currentLongitude = presence.currentLongitude,
                )
            )?.toDomain()?.let(::upsertLocal)
        }
        queries.selectLiveRunPresenceBySessionIdAndUserId(presence.sessionId, presence.userId).executeAsOne().toDomain()
    }

    override suspend fun getForSession(sessionId: String): List<LiveRunPresence> = safeDbCall(
        dispatcher,
        "Failed to get live run presence for session '$sessionId'",
    ) {
        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.getLiveRunPresence(sessionId)?.map { it.toDomain() }?.forEach(::upsertLocal)
        }
        queries.selectLiveRunPresenceBySessionId(sessionId).executeAsList().map { it.toDomain() }
    }

    override suspend fun getForUser(sessionId: String, userId: String): LiveRunPresence? = safeDbCall(
        dispatcher,
        "Failed to get live run presence for session '$sessionId' and user '$userId'",
    ) {
        getForSession(sessionId).firstOrNull { it.userId == userId }
    }

    override fun observeForSession(sessionId: String): Flow<List<LiveRunPresence>> =
        queries.selectLiveRunPresenceBySessionId(sessionId)
            .asFlow()
            .mapToList(dispatcher)
            .map { rows -> rows.map { it.toDomain() } }
            .catch { e -> throw RepositoryException("Failed to observe live run presence for session '$sessionId'", e) }

    private fun upsertLocal(presence: LiveRunPresence) {
        queries.upsertLiveRunPresence(
            id = presence.id,
            sessionId = presence.sessionId,
            userId = presence.userId,
            presenceState = presence.state.toDbValue(),
            lastSeenAt = presence.lastSeenAt.toEpochMilliseconds(),
            currentDistanceMeters = presence.currentDistanceMeters,
            currentDurationSeconds = presence.currentDurationSeconds,
            currentPaceSecondsPerKm = presence.currentPaceSecondsPerKm?.toLong(),
            currentLatitude = presence.currentLatitude,
            currentLongitude = presence.currentLongitude,
            updatedAt = presence.updatedAt.toEpochMilliseconds(),
        )
    }
}

private fun DbLiveRunPresence.toDomain(): LiveRunPresence = LiveRunPresence(
    id = id,
    sessionId = sessionId,
    userId = userId,
    state = RunPresenceState.valueOf(presenceState.uppercase()),
    lastSeenAt = Instant.fromEpochMilliseconds(lastSeenAt),
    currentDistanceMeters = currentDistanceMeters,
    currentDurationSeconds = currentDurationSeconds,
    currentPaceSecondsPerKm = currentPaceSecondsPerKm?.toInt(),
    currentLatitude = currentLatitude,
    currentLongitude = currentLongitude,
    updatedAt = Instant.fromEpochMilliseconds(updatedAt),
)

private fun RunPresenceState.toDbValue(): String = name.lowercase()
