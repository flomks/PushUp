package com.pushup.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.dto.CreateRunEventParticipantRequest
import com.pushup.data.api.dto.CreateRunEventRequest
import com.pushup.data.api.dto.RunEventDTO
import com.pushup.data.api.dto.RunEventParticipantDTO
import com.pushup.data.api.dto.UpdateRunEventRequest
import com.pushup.data.api.dto.UpdateRunEventParticipantRequest
import com.pushup.data.api.dto.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.db.RunEvent as DbRunEvent
import com.pushup.db.RunEventParticipant as DbRunEventParticipant
import com.pushup.domain.model.RunEvent
import com.pushup.domain.model.RunEventParticipant
import com.pushup.domain.model.RunEventStatus
import com.pushup.domain.model.RunMode
import com.pushup.domain.model.RunParticipantRole
import com.pushup.domain.model.RunParticipantStatus
import com.pushup.domain.model.RunVisibility
import com.pushup.domain.model.AvatarVisibility
import com.pushup.domain.model.User
import com.pushup.domain.repository.RunEventRepository
import com.pushup.domain.usecase.sync.NetworkMonitor
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

class RunEventRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
    private val clock: Clock = Clock.System,
    private val cloudSyncApi: CloudSyncApi? = null,
    private val networkMonitor: NetworkMonitor? = null,
) : RunEventRepository {

    private val queries get() = database.databaseQueries

    override suspend fun create(event: RunEvent, participants: List<RunEventParticipant>): RunEvent = safeDbCall(
        dispatcher,
        "Failed to create run event '${event.id}'",
    ) {
        upsertLocalEvent(event, participants)

        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.createRunEvent(event.toCreateRequest())
            cloudSyncApi?.createRunEventParticipants(participants.map { it.toCreateRequest() })
        }
        event
    }

    override suspend fun getById(eventId: String): RunEvent? = safeDbCall(
        dispatcher,
        "Failed to get run event '$eventId'",
    ) {
        queries.selectRunEventById(eventId).executeAsOneOrNull()?.toDomain()
            ?: fetchAndPersistRemoteEvent(eventId)
    }

    override suspend fun getUpcomingForUser(userId: String): List<RunEvent> = safeDbCall(
        dispatcher,
        "Failed to get upcoming run events for user '$userId'",
    ) {
        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.getRunEvents()?.forEach { eventDto ->
                val remoteParticipants = cloudSyncApi.getRunEventParticipants(eventDto.id).map { it.toDomain() }
                upsertLocalEvent(eventDto.toDomain(), remoteParticipants)
            }
        }
        queries.selectRunEventParticipantsByUserId(userId)
            .executeAsList()
            .mapNotNull { participant -> queries.selectRunEventById(participant.eventId).executeAsOneOrNull()?.toDomain() }
            .sortedBy { it.plannedStartAt.epochSeconds }
    }

    override suspend fun getParticipants(eventId: String): List<RunEventParticipant> = safeDbCall(
        dispatcher,
        "Failed to get run event participants for event '$eventId'",
    ) {
        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.getRunEventParticipants(eventId)?.let { remote ->
                val localEvent = queries.selectRunEventById(eventId).executeAsOneOrNull()?.toDomain()
                if (localEvent != null) {
                    upsertLocalEvent(localEvent, remote.map { it.toDomain() })
                }
            }
        }
        queries.selectRunEventParticipantsByEventId(eventId).executeAsList().map { it.toDomain() }
    }

    override suspend fun updateEventOrganizer(
        eventId: String,
        organizerUserId: String,
    ): RunEvent = safeDbCall(
        dispatcher,
        "Failed to update organizer for run event '$eventId'",
    ) {
        val event = queries.selectRunEventById(eventId).executeAsOneOrNull()
            ?: error("Run event not found: $eventId")
        val now = clock.now().toEpochMilliseconds()

        queries.updateRunEvent(
            createdBy = organizerUserId,
            title = event.title,
            description = event.description,
            mode = event.mode,
            visibility = event.visibility,
            plannedStartAt = event.plannedStartAt,
            plannedEndAt = event.plannedEndAt,
            checkInOpensAt = event.checkInOpensAt,
            status = event.status,
            locationName = event.locationName,
            updatedAt = now,
            id = event.id,
        )

        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.updateRunEvent(
                id = eventId,
                request = UpdateRunEventRequest(
                    createdBy = organizerUserId,
                ),
            )
        }

        queries.selectRunEventById(eventId).executeAsOne().toDomain()
    }

    override suspend fun updateParticipantRole(
        eventId: String,
        userId: String,
        role: RunParticipantRole,
    ): RunEventParticipant = safeDbCall(
        dispatcher,
        "Failed to update run event participant role for event '$eventId' and user '$userId'",
    ) {
        val existing = queries.selectRunEventParticipantByEventIdAndUserId(eventId, userId).executeAsOneOrNull()
            ?: error("Run event participant not found for event '$eventId' and user '$userId'")
        val now = clock.now().toEpochMilliseconds()

        queries.updateRunEventParticipant(
            eventId = existing.eventId,
            userId = existing.userId,
            role = role.toDbValue(),
            status = existing.status,
            invitedBy = existing.invitedBy,
            invitedAt = existing.invitedAt,
            respondedAt = existing.respondedAt,
            checkedInAt = existing.checkedInAt,
            updatedAt = now,
            id = existing.id,
        )

        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.updateRunEventParticipant(
                eventId = eventId,
                userId = userId,
                request = UpdateRunEventParticipantRequest(
                    role = role.toDbValue(),
                ),
            )
        }

        queries.selectRunEventParticipantByEventIdAndUserId(eventId, userId).executeAsOne().toDomain()
    }

    override suspend fun updateParticipantStatus(
        eventId: String,
        userId: String,
        status: RunParticipantStatus,
    ): RunEventParticipant = safeDbCall(
        dispatcher,
        "Failed to update run event participant status for event '$eventId' and user '$userId'",
    ) {
        val existing = queries.selectRunEventParticipantByEventIdAndUserId(eventId, userId).executeAsOneOrNull()
            ?: error("Run event participant not found for event '$eventId' and user '$userId'")
        val now = clock.now().toEpochMilliseconds()
        val respondedAt = when (status) {
            RunParticipantStatus.ACCEPTED, RunParticipantStatus.DECLINED -> now
            else -> existing.respondedAt
        }
        val checkedInAt = if (status == RunParticipantStatus.CHECKED_IN) now else existing.checkedInAt

        queries.updateRunEventParticipant(
            eventId = existing.eventId,
            userId = existing.userId,
            role = existing.role,
            status = status.toDbEventValue(),
            invitedBy = existing.invitedBy,
            invitedAt = existing.invitedAt,
            respondedAt = respondedAt,
            checkedInAt = checkedInAt,
            updatedAt = now,
            id = existing.id,
        )
        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.updateRunEventParticipant(
                eventId = eventId,
                userId = userId,
                request = UpdateRunEventParticipantRequest(
                    status = status.toDbEventValue(),
                    respondedAt = respondedAt?.let(Instant::fromEpochMilliseconds)?.toString(),
                    checkedInAt = checkedInAt?.let(Instant::fromEpochMilliseconds)?.toString(),
                ),
            )
        }
        queries.selectRunEventParticipantByEventIdAndUserId(eventId, userId).executeAsOne().toDomain()
    }

    override suspend fun removeParticipant(eventId: String, userId: String): Unit = safeDbCall(
        dispatcher,
        "Failed to remove run event participant for event '$eventId' and user '$userId'",
    ) {
        queries.deleteRunEventParticipant(eventId, userId)
        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.deleteRunEventParticipant(eventId, userId)
        }
    }

    override suspend fun deleteEvent(eventId: String): Unit = safeDbCall(
        dispatcher,
        "Failed to delete run event '$eventId'",
    ) {
        queries.deleteRunEvent(eventId)
        if (networkMonitor?.isConnected() == true) {
            cloudSyncApi?.deleteRunEvent(eventId)
        }
    }

    override fun observeUpcomingForUser(userId: String): Flow<List<RunEvent>> =
        queries.selectRunEventParticipantsByUserId(userId)
            .asFlow()
            .mapToList(dispatcher)
            .map { participants ->
                participants.mapNotNull { participant ->
                    queries.selectRunEventById(participant.eventId).executeAsOneOrNull()?.toDomain()
                }.sortedBy { it.plannedStartAt.epochSeconds }
            }
            .catch { e ->
                throw RepositoryException("Failed to observe upcoming run events for user '$userId'", e)
            }

    private suspend fun fetchAndPersistRemoteEvent(eventId: String): RunEvent? {
        if (networkMonitor?.isConnected() != true) return null
        val event = cloudSyncApi?.getRunEvent(eventId)?.toDomain() ?: return null
        val participants = cloudSyncApi.getRunEventParticipants(eventId).map { it.toDomain() }
        upsertLocalEvent(event, participants)
        return event
    }

    private fun upsertLocalEvent(
        event: RunEvent,
        participants: List<RunEventParticipant>,
    ) {
        database.transaction {
            ensureLocalUsersExist(event, participants)
            val existingEvent = queries.selectRunEventById(event.id).executeAsOneOrNull()
            if (existingEvent == null) {
                queries.insertRunEvent(
                    id = event.id,
                    createdBy = event.createdBy,
                    title = event.title,
                    description = event.description,
                    mode = event.mode.toDbValue(),
                    visibility = event.visibility.toDbValue(),
                    plannedStartAt = event.plannedStartAt.toEpochMilliseconds(),
                    plannedEndAt = event.plannedEndAt?.toEpochMilliseconds(),
                    checkInOpensAt = event.checkInOpensAt.toEpochMilliseconds(),
                    status = event.status.toDbValue(),
                    locationName = event.locationName,
                    createdAt = event.createdAt.toEpochMilliseconds(),
                    updatedAt = event.updatedAt.toEpochMilliseconds(),
                )
            } else {
                queries.updateRunEvent(
                    createdBy = event.createdBy,
                    title = event.title,
                    description = event.description,
                    mode = event.mode.toDbValue(),
                    visibility = event.visibility.toDbValue(),
                    plannedStartAt = event.plannedStartAt.toEpochMilliseconds(),
                    plannedEndAt = event.plannedEndAt?.toEpochMilliseconds(),
                    checkInOpensAt = event.checkInOpensAt.toEpochMilliseconds(),
                    status = event.status.toDbValue(),
                    locationName = event.locationName,
                    updatedAt = event.updatedAt.toEpochMilliseconds(),
                    id = event.id,
                )
            }
            participants.forEach { participant ->
                val existing = queries.selectRunEventParticipantByEventIdAndUserId(participant.eventId, participant.userId)
                    .executeAsOneOrNull()
                if (existing == null) {
                    queries.insertRunEventParticipant(
                        id = participant.id,
                        eventId = participant.eventId,
                        userId = participant.userId,
                        role = participant.role.toDbValue(),
                        status = participant.status.toDbEventValue(),
                        invitedBy = participant.invitedBy,
                        invitedAt = participant.invitedAt.toEpochMilliseconds(),
                        respondedAt = participant.respondedAt?.toEpochMilliseconds(),
                        checkedInAt = participant.checkedInAt?.toEpochMilliseconds(),
                        createdAt = participant.createdAt.toEpochMilliseconds(),
                        updatedAt = participant.updatedAt.toEpochMilliseconds(),
                    )
                } else {
                    queries.updateRunEventParticipant(
                        eventId = participant.eventId,
                        userId = participant.userId,
                        role = participant.role.toDbValue(),
                        status = participant.status.toDbEventValue(),
                        invitedBy = participant.invitedBy,
                        invitedAt = participant.invitedAt.toEpochMilliseconds(),
                        respondedAt = participant.respondedAt?.toEpochMilliseconds(),
                        checkedInAt = participant.checkedInAt?.toEpochMilliseconds(),
                        updatedAt = participant.updatedAt.toEpochMilliseconds(),
                        id = existing.id,
                    )
                }
            }
        }
    }

    private fun ensureLocalUsersExist(
        event: RunEvent,
        participants: List<RunEventParticipant>,
    ) {
        val now = clock.now()
        val requiredUserIds = buildSet {
            add(event.createdBy)
            participants.forEach { participant ->
                add(participant.userId)
                participant.invitedBy?.let(::add)
            }
        }

        requiredUserIds.forEach { userId ->
            val existing = queries.selectUserById(userId).executeAsOneOrNull()
            if (existing == null) {
                val stub = localStubUser(userId = userId, now = now)
                queries.upsertUser(
                    id = stub.id,
                    email = stub.email,
                    username = stub.username,
                    displayName = stub.displayName,
                    avatarUrl = stub.avatarUrl,
                    avatarVisibility = stub.avatarVisibility.toDbValue(),
                    createdAt = stub.createdAt.toEpochMilliseconds(),
                    syncedAt = stub.lastSyncedAt.toEpochMilliseconds(),
                )
            }
        }
    }

    private fun localStubUser(
        userId: String,
        now: Instant,
    ): User = User(
        id = userId,
        email = "unknown+$userId@local.pushup",
        username = null,
        displayName = "Runner",
        avatarUrl = null,
        avatarVisibility = AvatarVisibility.EVERYONE,
        // Stub users only exist to satisfy local FK relationships for social
        // features. They must never outrank the authenticated profile in
        // `selectCurrentUser()`, which currently orders by `createdAt DESC`.
        createdAt = Instant.fromEpochMilliseconds(0),
        lastSyncedAt = Instant.fromEpochMilliseconds(0),
    )
}

private fun RunEvent.toCreateRequest(): CreateRunEventRequest = CreateRunEventRequest(
    id = id,
    createdBy = createdBy,
    title = title,
    description = description,
    mode = mode.toDbValue(),
    visibility = visibility.toDbValue(),
    plannedStartAt = plannedStartAt.toString(),
    plannedEndAt = plannedEndAt?.toString(),
    checkInOpensAt = checkInOpensAt.toString(),
    status = status.toDbValue(),
    locationName = locationName,
)

private fun RunEventParticipant.toCreateRequest(): CreateRunEventParticipantRequest = CreateRunEventParticipantRequest(
    id = id,
    eventId = eventId,
    userId = userId,
    role = role.toDbValue(),
    status = status.toDbEventValue(),
    invitedBy = invitedBy,
    invitedAt = invitedAt.toString(),
    respondedAt = respondedAt?.toString(),
    checkedInAt = checkedInAt?.toString(),
)

private fun DbRunEvent.toDomain(): RunEvent = RunEvent(
    id = id,
    createdBy = createdBy,
    title = title,
    description = description,
    mode = RunMode.valueOf(mode.uppercase()),
    visibility = runVisibilityFromDbValue(visibility),
    plannedStartAt = Instant.fromEpochMilliseconds(plannedStartAt),
    plannedEndAt = plannedEndAt?.let(Instant::fromEpochMilliseconds),
    checkInOpensAt = Instant.fromEpochMilliseconds(checkInOpensAt),
    locationName = locationName,
    status = runEventStatusFromDbValue(status),
    createdAt = Instant.fromEpochMilliseconds(createdAt),
    updatedAt = Instant.fromEpochMilliseconds(updatedAt),
)

private fun DbRunEventParticipant.toDomain(): RunEventParticipant = RunEventParticipant(
    id = id,
    eventId = eventId,
    userId = userId,
    role = RunParticipantRole.valueOf(role.uppercase()),
    status = runParticipantStatusFromDbEventValue(status),
    invitedBy = invitedBy,
    invitedAt = Instant.fromEpochMilliseconds(invitedAt ?: createdAt),
    respondedAt = respondedAt?.let(Instant::fromEpochMilliseconds),
    checkedInAt = checkedInAt?.let(Instant::fromEpochMilliseconds),
    createdAt = Instant.fromEpochMilliseconds(createdAt),
    updatedAt = Instant.fromEpochMilliseconds(updatedAt),
)

private fun RunMode.toDbValue(): String = name.lowercase()
private fun RunEventStatus.toDbValue(): String = name.lowercase()
private fun RunParticipantRole.toDbValue(): String = name.lowercase()
private fun RunVisibility.toDbValue(): String = when (this) {
    RunVisibility.PRIVATE -> "private"
    RunVisibility.FRIENDS -> "friends"
    RunVisibility.INVITE_ONLY -> "invite_only"
}
private fun runVisibilityFromDbValue(value: String): RunVisibility = when (value.lowercase()) {
    "private" -> RunVisibility.PRIVATE
    "friends" -> RunVisibility.FRIENDS
    "invite_only" -> RunVisibility.INVITE_ONLY
    else -> error("Unknown RunVisibility db value: $value")
}
private fun runEventStatusFromDbValue(value: String): RunEventStatus = when (value.lowercase()) {
    "planned" -> RunEventStatus.PLANNED
    "check_in_open" -> RunEventStatus.CHECK_IN_OPEN
    "live" -> RunEventStatus.LIVE
    "completed" -> RunEventStatus.COMPLETED
    "cancelled" -> RunEventStatus.CANCELLED
    else -> error("Unknown RunEventStatus db value: $value")
}
private fun RunParticipantStatus.toDbEventValue(): String = when (this) {
    RunParticipantStatus.INVITED -> "invited"
    RunParticipantStatus.ACCEPTED -> "accepted"
    RunParticipantStatus.DECLINED -> "declined"
    RunParticipantStatus.CHECKED_IN -> "checked_in"
    else -> error("Run event status does not support value: $this")
}
private fun runParticipantStatusFromDbEventValue(value: String): RunParticipantStatus = when (value.lowercase()) {
    "invited" -> RunParticipantStatus.INVITED
    "accepted" -> RunParticipantStatus.ACCEPTED
    "declined" -> RunParticipantStatus.DECLINED
    "checked_in" -> RunParticipantStatus.CHECKED_IN
    else -> error("Unknown RunEventParticipant status db value: $value")
}
