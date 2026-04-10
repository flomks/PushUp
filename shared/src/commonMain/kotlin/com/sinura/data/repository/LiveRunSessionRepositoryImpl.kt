package com.sinura.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import app.cash.sqldelight.coroutines.mapToOneOrNull
import com.sinura.data.api.CloudSyncApi
import com.sinura.data.api.dto.CreateLiveRunParticipantRequest
import com.sinura.data.api.dto.CreateLiveRunSessionRequest
import com.sinura.data.api.dto.UpdateLiveRunParticipantRequest
import com.sinura.data.api.dto.UpdateLiveRunSessionRequest
import com.sinura.data.api.dto.toDomain
import com.sinura.db.LiveRunParticipant as DbLiveRunParticipant
import com.sinura.db.LiveRunSession as DbLiveRunSession
import com.sinura.db.SinuraDatabase
import com.sinura.domain.model.LiveRunParticipant
import com.sinura.domain.model.LiveRunSession
import com.sinura.domain.model.LiveRunSessionState
import com.sinura.domain.model.LiveRunSourceType
import com.sinura.domain.model.RunMode
import com.sinura.domain.model.RunParticipantStatus
import com.sinura.domain.model.RunVisibility
import com.sinura.domain.repository.LiveRunSessionRepository
import com.sinura.domain.usecase.sync.NetworkMonitor
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

class LiveRunSessionRepositoryImpl(
    private val database: SinuraDatabase,
    private val dispatcher: CoroutineDispatcher,
    private val clock: Clock = Clock.System,
    private val cloudSyncApi: CloudSyncApi? = null,
    private val networkMonitor: NetworkMonitor? = null,
) : LiveRunSessionRepository {

    private val queries get() = database.databaseQueries

    override suspend fun create(session: LiveRunSession, leader: LiveRunParticipant): LiveRunSession = safeDbCall(
        dispatcher,
        "Failed to create live run session '${session.id}'",
    ) {
        upsertLocalSession(session, leader)
        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.createLiveRunSession(session.toCreateRequest())
            cloudSyncApi?.createLiveRunParticipants(listOf(leader.toCreateRequest()))
        }
        session
    }

    override suspend fun getById(sessionId: String): LiveRunSession? = safeDbCall(
        dispatcher,
        "Failed to get live run session '$sessionId'",
    ) {
        queries.selectLiveRunSessionById(sessionId).executeAsOneOrNull()?.toDomain()
            ?: fetchAndPersistRemoteSession(sessionId)
    }

    override suspend fun getParticipants(sessionId: String): List<LiveRunParticipant> = safeDbCall(
        dispatcher,
        "Failed to get live run participants for session '$sessionId'",
    ) {
        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.getLiveRunParticipants(sessionId)?.map { it.toDomain() }?.forEach(::upsertLocalParticipant)
        }
        queries.selectLiveRunParticipantsBySessionId(sessionId).executeAsList().map { it.toDomain() }
    }

    override suspend fun upsertParticipant(participant: LiveRunParticipant): LiveRunParticipant = safeDbCall(
        dispatcher,
        "Failed to upsert live run participant '${participant.id}'",
    ) {
        upsertLocalParticipant(participant)
        if (networkMonitor?.isConnected() == true) {
            val existingRemote = cloudSyncApi?.updateLiveRunParticipant(
                sessionId = participant.sessionId,
                userId = participant.userId,
                request = UpdateLiveRunParticipantRequest(
                    status = participant.status.toDbLiveValue(),
                    becameActiveAt = participant.becameActiveAt?.toString(),
                    finishedAt = participant.finishedAt?.toString(),
                    leftAt = participant.leftAt?.toString(),
                    isLeader = participant.isLeader,
                ),
            )
            if (existingRemote == null) {
                cloudSyncApi?.createLiveRunParticipants(listOf(participant.toCreateRequest()))
            }
        }
        queries.selectLiveRunParticipantBySessionIdAndUserId(participant.sessionId, participant.userId).executeAsOne().toDomain()
    }

    override suspend fun updateLeader(sessionId: String, newLeaderUserId: String): LiveRunSession = safeDbCall(
        dispatcher,
        "Failed to update leader for live run session '$sessionId'",
    ) {
        val session = queries.selectLiveRunSessionById(sessionId).executeAsOneOrNull()
            ?: error("Live run session not found: $sessionId")
        val participants = queries.selectLiveRunParticipantsBySessionId(sessionId).executeAsList()
        val now = clock.now().toEpochMilliseconds()
        participants.forEach { participant ->
            queries.updateLiveRunParticipant(
                sessionId = participant.sessionId,
                userId = participant.userId,
                status = participant.status,
                joinedAt = participant.joinedAt,
                becameActiveAt = participant.becameActiveAt,
                finishedAt = participant.finishedAt,
                leftAt = participant.leftAt,
                isLeader = if (participant.userId == newLeaderUserId) 1L else 0L,
                updatedAt = now,
                id = participant.id,
            )
        }
        queries.updateLiveRunSession(
            sourceType = session.sourceType,
            linkedEventId = session.linkedEventId,
            leaderUserId = newLeaderUserId,
            visibility = session.visibility,
            mode = session.mode,
            state = session.state,
            startedAt = session.startedAt,
            cooldownStartedAt = session.cooldownStartedAt,
            endedAt = session.endedAt,
            lastActivityAt = session.lastActivityAt,
            maxEndsAt = session.maxEndsAt,
            updatedAt = now,
            id = session.id,
        )
        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.updateLiveRunSession(
                id = sessionId,
                request = UpdateLiveRunSessionRequest(
                    leaderUserId = newLeaderUserId,
                    lastActivityAt = Instant.fromEpochMilliseconds(now).toString(),
                ),
            )
            participants.forEach { participant ->
                cloudSyncApi?.updateLiveRunParticipant(
                    sessionId = participant.sessionId,
                    userId = participant.userId,
                    request = UpdateLiveRunParticipantRequest(
                        isLeader = participant.userId == newLeaderUserId,
                    ),
                )
            }
        }
        queries.selectLiveRunSessionById(sessionId).executeAsOne().toDomain()
    }

    override suspend fun updateState(sessionId: String, state: LiveRunSessionState): LiveRunSession = safeDbCall(
        dispatcher,
        "Failed to update state for live run session '$sessionId'",
    ) {
        val session = queries.selectLiveRunSessionById(sessionId).executeAsOneOrNull()
            ?: error("Live run session not found: $sessionId")
        val now = clock.now().toEpochMilliseconds()
        queries.updateLiveRunSession(
            sourceType = session.sourceType,
            linkedEventId = session.linkedEventId,
            leaderUserId = session.leaderUserId,
            visibility = session.visibility,
            mode = session.mode,
            state = state.toDbValue(),
            startedAt = session.startedAt,
            cooldownStartedAt = if (state == LiveRunSessionState.COOLDOWN) now else session.cooldownStartedAt,
            endedAt = if (state == LiveRunSessionState.FINISHED) now else session.endedAt,
            lastActivityAt = now,
            maxEndsAt = session.maxEndsAt,
            updatedAt = now,
            id = session.id,
        )
        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.updateLiveRunSession(
                id = sessionId,
                request = UpdateLiveRunSessionRequest(
                    state = state.toDbValue(),
                    cooldownStartedAt = if (state == LiveRunSessionState.COOLDOWN) Instant.fromEpochMilliseconds(now).toString() else null,
                    endedAt = if (state == LiveRunSessionState.FINISHED) Instant.fromEpochMilliseconds(now).toString() else null,
                    lastActivityAt = Instant.fromEpochMilliseconds(now).toString(),
                ),
            )
        }
        queries.selectLiveRunSessionById(sessionId).executeAsOne().toDomain()
    }

    override suspend fun getFriendsActiveSessions(userId: String): List<LiveRunSession> = safeDbCall(
        dispatcher,
        "Failed to get friends active live run sessions for user '$userId'",
    ) {
        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.getLiveRunSessions()
                ?.map { it.toDomain() }
                ?.filter { it.state != LiveRunSessionState.FINISHED }
                ?.forEach { session ->
                    val leader = cloudSyncApi.getLiveRunParticipants(session.id)
                        .map { it.toDomain() }
                        .firstOrNull { it.userId == session.leaderUserId }
                        ?: LiveRunParticipant(
                            id = session.id,
                            sessionId = session.id,
                            userId = session.leaderUserId,
                            status = RunParticipantStatus.ACTIVE,
                            joinedAt = session.startedAt,
                            becameActiveAt = session.startedAt,
                            finishedAt = null,
                            leftAt = null,
                            isLeader = true,
                            createdAt = session.createdAt,
                            updatedAt = session.updatedAt,
                        )
                    upsertLocalSession(session, leader)
                }
        }
        queries.selectLiveRunSessionsByState(LiveRunSessionState.LIVE.toDbValue())
            .executeAsList()
            .map { it.toDomain() }
    }

    override fun observeSession(sessionId: String): Flow<LiveRunSession?> =
        queries.selectLiveRunSessionById(sessionId)
            .asFlow()
            .mapToOneOrNull(dispatcher)
            .map { it?.toDomain() }
            .catch { e -> throw RepositoryException("Failed to observe live run session '$sessionId'", e) }

    override fun observeParticipants(sessionId: String): Flow<List<LiveRunParticipant>> =
        queries.selectLiveRunParticipantsBySessionId(sessionId)
            .asFlow()
            .mapToList(dispatcher)
            .map { rows -> rows.map { it.toDomain() } }
            .catch { e -> throw RepositoryException("Failed to observe live run participants for session '$sessionId'", e) }

    private suspend fun fetchAndPersistRemoteSession(sessionId: String): LiveRunSession? {
        if (networkMonitor?.isConnected() != true) return null
        val session = cloudSyncApi?.getLiveRunSession(sessionId)?.toDomain() ?: return null
        val remoteParticipants = cloudSyncApi.getLiveRunParticipants(sessionId).map { it.toDomain() }
        val leader = remoteParticipants.firstOrNull { it.userId == session.leaderUserId }
            ?: return session
        upsertLocalSession(session, leader)
        remoteParticipants.filterNot { it.userId == leader.userId }.forEach(::upsertLocalParticipant)
        return session
    }

    private fun upsertLocalSession(
        session: LiveRunSession,
        leader: LiveRunParticipant,
    ) {
        database.transaction {
            queries.insertLiveRunSession(
                id = session.id,
                sourceType = session.sourceType.toDbValue(),
                linkedEventId = session.linkedEventId,
                leaderUserId = session.leaderUserId,
                visibility = session.visibility.toDbValue(),
                mode = session.mode.toDbValue(),
                state = session.state.toDbValue(),
                startedAt = session.startedAt.toEpochMilliseconds(),
                cooldownStartedAt = session.cooldownStartedAt?.toEpochMilliseconds(),
                endedAt = session.endedAt?.toEpochMilliseconds(),
                lastActivityAt = session.lastActivityAt.toEpochMilliseconds(),
                maxEndsAt = session.maxEndsAt.toEpochMilliseconds(),
                createdAt = session.createdAt.toEpochMilliseconds(),
                updatedAt = session.updatedAt.toEpochMilliseconds(),
            )
            upsertLocalParticipant(leader)
        }
    }

    private fun upsertLocalParticipant(participant: LiveRunParticipant) {
        val existing = queries.selectLiveRunParticipantBySessionIdAndUserId(participant.sessionId, participant.userId)
            .executeAsOneOrNull()
        if (existing == null) {
            queries.insertLiveRunParticipant(
                id = participant.id,
                sessionId = participant.sessionId,
                userId = participant.userId,
                status = participant.status.toDbLiveValue(),
                joinedAt = participant.joinedAt.toEpochMilliseconds(),
                becameActiveAt = participant.becameActiveAt?.toEpochMilliseconds(),
                finishedAt = participant.finishedAt?.toEpochMilliseconds(),
                leftAt = participant.leftAt?.toEpochMilliseconds(),
                isLeader = if (participant.isLeader) 1L else 0L,
                createdAt = participant.createdAt.toEpochMilliseconds(),
                updatedAt = participant.updatedAt.toEpochMilliseconds(),
            )
        } else {
            queries.updateLiveRunParticipant(
                sessionId = participant.sessionId,
                userId = participant.userId,
                status = participant.status.toDbLiveValue(),
                joinedAt = participant.joinedAt.toEpochMilliseconds(),
                becameActiveAt = participant.becameActiveAt?.toEpochMilliseconds(),
                finishedAt = participant.finishedAt?.toEpochMilliseconds(),
                leftAt = participant.leftAt?.toEpochMilliseconds(),
                isLeader = if (participant.isLeader) 1L else 0L,
                updatedAt = participant.updatedAt.toEpochMilliseconds(),
                id = existing.id,
            )
        }
    }
}

private fun LiveRunSession.toCreateRequest(): CreateLiveRunSessionRequest = CreateLiveRunSessionRequest(
    id = id,
    sourceType = sourceType.toDbValue(),
    linkedEventId = linkedEventId,
    leaderUserId = leaderUserId,
    visibility = visibility.toDbValue(),
    mode = mode.toDbValue(),
    state = state.toDbValue(),
    startedAt = startedAt.toString(),
    cooldownStartedAt = cooldownStartedAt?.toString(),
    endedAt = endedAt?.toString(),
    lastActivityAt = lastActivityAt.toString(),
    maxEndsAt = maxEndsAt.toString(),
)

private fun LiveRunParticipant.toCreateRequest(): CreateLiveRunParticipantRequest = CreateLiveRunParticipantRequest(
    id = id,
    sessionId = sessionId,
    userId = userId,
    status = status.toDbLiveValue(),
    joinedAt = joinedAt.toString(),
    becameActiveAt = becameActiveAt?.toString(),
    finishedAt = finishedAt?.toString(),
    leftAt = leftAt?.toString(),
    isLeader = isLeader,
)

private fun DbLiveRunSession.toDomain(): LiveRunSession = LiveRunSession(
    id = id,
    sourceType = LiveRunSourceType.valueOf(sourceType.uppercase()),
    linkedEventId = linkedEventId,
    leaderUserId = leaderUserId,
    visibility = liveRunVisibilityFromDbValue(visibility),
    mode = RunMode.valueOf(mode.uppercase()),
    state = LiveRunSessionState.valueOf(state.uppercase()),
    startedAt = Instant.fromEpochMilliseconds(startedAt),
    cooldownStartedAt = cooldownStartedAt?.let(Instant::fromEpochMilliseconds),
    endedAt = endedAt?.let(Instant::fromEpochMilliseconds),
    lastActivityAt = Instant.fromEpochMilliseconds(lastActivityAt),
    maxEndsAt = Instant.fromEpochMilliseconds(maxEndsAt),
    createdAt = Instant.fromEpochMilliseconds(createdAt),
    updatedAt = Instant.fromEpochMilliseconds(updatedAt),
)

private fun DbLiveRunParticipant.toDomain(): LiveRunParticipant = LiveRunParticipant(
    id = id,
    sessionId = sessionId,
    userId = userId,
    status = runParticipantStatusFromDbLiveValue(status),
    joinedAt = Instant.fromEpochMilliseconds(joinedAt),
    becameActiveAt = becameActiveAt?.let(Instant::fromEpochMilliseconds),
    finishedAt = finishedAt?.let(Instant::fromEpochMilliseconds),
    leftAt = leftAt?.let(Instant::fromEpochMilliseconds),
    isLeader = isLeader != 0L,
    createdAt = Instant.fromEpochMilliseconds(createdAt),
    updatedAt = Instant.fromEpochMilliseconds(updatedAt),
)

private fun LiveRunSourceType.toDbValue(): String = name.lowercase()
private fun LiveRunSessionState.toDbValue(): String = name.lowercase()
private fun RunMode.toDbValue(): String = name.lowercase()
private fun RunVisibility.toDbValue(): String = when (this) {
    RunVisibility.PRIVATE -> "private"
    RunVisibility.FRIENDS -> "friends"
    RunVisibility.INVITE_ONLY -> "invite_only"
}
private fun liveRunVisibilityFromDbValue(value: String): RunVisibility = when (value.lowercase()) {
    "private" -> RunVisibility.PRIVATE
    "friends" -> RunVisibility.FRIENDS
    "invite_only" -> RunVisibility.INVITE_ONLY
    else -> error("Unknown RunVisibility db value: $value")
}
private fun RunParticipantStatus.toDbLiveValue(): String = when (this) {
    RunParticipantStatus.INVITED -> "invited"
    RunParticipantStatus.JOINED -> "joined"
    RunParticipantStatus.ACTIVE -> "active"
    RunParticipantStatus.PAUSED -> "paused"
    RunParticipantStatus.FINISHED -> "finished"
    RunParticipantStatus.LEFT -> "left"
    else -> error("Live run participant status does not support value: $this")
}
private fun runParticipantStatusFromDbLiveValue(value: String): RunParticipantStatus = when (value.lowercase()) {
    "invited" -> RunParticipantStatus.INVITED
    "joined" -> RunParticipantStatus.JOINED
    "active" -> RunParticipantStatus.ACTIVE
    "paused" -> RunParticipantStatus.PAUSED
    "finished" -> RunParticipantStatus.FINISHED
    "left" -> RunParticipantStatus.LEFT
    else -> error("Unknown LiveRunParticipant status db value: $value")
}
