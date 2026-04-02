package com.pushup.data.api.dto

import com.pushup.domain.model.LiveRunParticipant
import com.pushup.domain.model.LiveRunPresence
import com.pushup.domain.model.LiveRunSession
import com.pushup.domain.model.LiveRunSessionState
import com.pushup.domain.model.LiveRunSourceType
import com.pushup.domain.model.RunEvent
import com.pushup.domain.model.RunEventParticipant
import com.pushup.domain.model.RunEventStatus
import com.pushup.domain.model.RunMode
import com.pushup.domain.model.RunParticipantRole
import com.pushup.domain.model.RunParticipantStatus
import com.pushup.domain.model.RunPresenceState
import com.pushup.domain.model.RunVisibility
import kotlinx.datetime.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class RunEventDTO(
    @SerialName("id") val id: String,
    @SerialName("created_by") val createdBy: String,
    @SerialName("title") val title: String,
    @SerialName("description") val description: String? = null,
    @SerialName("mode") val mode: String,
    @SerialName("visibility") val visibility: String,
    @SerialName("planned_start_at") val plannedStartAt: String,
    @SerialName("planned_end_at") val plannedEndAt: String? = null,
    @SerialName("check_in_opens_at") val checkInOpensAt: String,
    @SerialName("status") val status: String,
    @SerialName("location_name") val locationName: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)

@Serializable
data class CreateRunEventRequest(
    @SerialName("id") val id: String,
    @SerialName("created_by") val createdBy: String,
    @SerialName("title") val title: String,
    @SerialName("description") val description: String? = null,
    @SerialName("mode") val mode: String,
    @SerialName("visibility") val visibility: String,
    @SerialName("planned_start_at") val plannedStartAt: String,
    @SerialName("planned_end_at") val plannedEndAt: String? = null,
    @SerialName("check_in_opens_at") val checkInOpensAt: String,
    @SerialName("status") val status: String,
    @SerialName("location_name") val locationName: String? = null,
)

@Serializable
data class UpdateRunEventRequest(
    @SerialName("title") val title: String? = null,
    @SerialName("description") val description: String? = null,
    @SerialName("mode") val mode: String? = null,
    @SerialName("visibility") val visibility: String? = null,
    @SerialName("planned_start_at") val plannedStartAt: String? = null,
    @SerialName("planned_end_at") val plannedEndAt: String? = null,
    @SerialName("check_in_opens_at") val checkInOpensAt: String? = null,
    @SerialName("status") val status: String? = null,
    @SerialName("location_name") val locationName: String? = null,
)

@Serializable
data class RunEventParticipantDTO(
    @SerialName("id") val id: String,
    @SerialName("event_id") val eventId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("role") val role: String,
    @SerialName("status") val status: String,
    @SerialName("invited_by") val invitedBy: String? = null,
    @SerialName("invited_at") val invitedAt: String? = null,
    @SerialName("responded_at") val respondedAt: String? = null,
    @SerialName("checked_in_at") val checkedInAt: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)

@Serializable
data class CreateRunEventParticipantRequest(
    @SerialName("id") val id: String,
    @SerialName("event_id") val eventId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("role") val role: String,
    @SerialName("status") val status: String,
    @SerialName("invited_by") val invitedBy: String? = null,
    @SerialName("invited_at") val invitedAt: String? = null,
    @SerialName("responded_at") val respondedAt: String? = null,
    @SerialName("checked_in_at") val checkedInAt: String? = null,
)

@Serializable
data class UpdateRunEventParticipantRequest(
    @SerialName("role") val role: String? = null,
    @SerialName("status") val status: String? = null,
    @SerialName("responded_at") val respondedAt: String? = null,
    @SerialName("checked_in_at") val checkedInAt: String? = null,
)

@Serializable
data class LiveRunSessionDTO(
    @SerialName("id") val id: String,
    @SerialName("source_type") val sourceType: String,
    @SerialName("linked_event_id") val linkedEventId: String? = null,
    @SerialName("leader_user_id") val leaderUserId: String,
    @SerialName("visibility") val visibility: String,
    @SerialName("mode") val mode: String,
    @SerialName("state") val state: String,
    @SerialName("started_at") val startedAt: String,
    @SerialName("cooldown_started_at") val cooldownStartedAt: String? = null,
    @SerialName("ended_at") val endedAt: String? = null,
    @SerialName("last_activity_at") val lastActivityAt: String,
    @SerialName("max_ends_at") val maxEndsAt: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)

@Serializable
data class CreateLiveRunSessionRequest(
    @SerialName("id") val id: String,
    @SerialName("source_type") val sourceType: String,
    @SerialName("linked_event_id") val linkedEventId: String? = null,
    @SerialName("leader_user_id") val leaderUserId: String,
    @SerialName("visibility") val visibility: String,
    @SerialName("mode") val mode: String,
    @SerialName("state") val state: String,
    @SerialName("started_at") val startedAt: String,
    @SerialName("cooldown_started_at") val cooldownStartedAt: String? = null,
    @SerialName("ended_at") val endedAt: String? = null,
    @SerialName("last_activity_at") val lastActivityAt: String,
    @SerialName("max_ends_at") val maxEndsAt: String,
)

@Serializable
data class UpdateLiveRunSessionRequest(
    @SerialName("leader_user_id") val leaderUserId: String? = null,
    @SerialName("visibility") val visibility: String? = null,
    @SerialName("mode") val mode: String? = null,
    @SerialName("state") val state: String? = null,
    @SerialName("cooldown_started_at") val cooldownStartedAt: String? = null,
    @SerialName("ended_at") val endedAt: String? = null,
    @SerialName("last_activity_at") val lastActivityAt: String? = null,
)

@Serializable
data class LiveRunParticipantDTO(
    @SerialName("id") val id: String,
    @SerialName("session_id") val sessionId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("status") val status: String,
    @SerialName("joined_at") val joinedAt: String,
    @SerialName("became_active_at") val becameActiveAt: String? = null,
    @SerialName("finished_at") val finishedAt: String? = null,
    @SerialName("left_at") val leftAt: String? = null,
    @SerialName("is_leader") val isLeader: Boolean = false,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
)

@Serializable
data class CreateLiveRunParticipantRequest(
    @SerialName("id") val id: String,
    @SerialName("session_id") val sessionId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("status") val status: String,
    @SerialName("joined_at") val joinedAt: String,
    @SerialName("became_active_at") val becameActiveAt: String? = null,
    @SerialName("finished_at") val finishedAt: String? = null,
    @SerialName("left_at") val leftAt: String? = null,
    @SerialName("is_leader") val isLeader: Boolean = false,
)

@Serializable
data class UpdateLiveRunParticipantRequest(
    @SerialName("status") val status: String? = null,
    @SerialName("became_active_at") val becameActiveAt: String? = null,
    @SerialName("finished_at") val finishedAt: String? = null,
    @SerialName("left_at") val leftAt: String? = null,
    @SerialName("is_leader") val isLeader: Boolean? = null,
)

@Serializable
data class LiveRunPresenceDTO(
    @SerialName("id") val id: String,
    @SerialName("session_id") val sessionId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("presence_state") val presenceState: String,
    @SerialName("last_seen_at") val lastSeenAt: String,
    @SerialName("current_distance_meters") val currentDistanceMeters: Double = 0.0,
    @SerialName("current_duration_seconds") val currentDurationSeconds: Int = 0,
    @SerialName("current_pace_seconds_per_km") val currentPaceSecondsPerKm: Int? = null,
    @SerialName("current_latitude") val currentLatitude: Double? = null,
    @SerialName("current_longitude") val currentLongitude: Double? = null,
    @SerialName("updated_at") val updatedAt: String,
)

@Serializable
data class UpsertLiveRunPresenceRequest(
    @SerialName("id") val id: String,
    @SerialName("session_id") val sessionId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("presence_state") val presenceState: String,
    @SerialName("last_seen_at") val lastSeenAt: String,
    @SerialName("current_distance_meters") val currentDistanceMeters: Double = 0.0,
    @SerialName("current_duration_seconds") val currentDurationSeconds: Int = 0,
    @SerialName("current_pace_seconds_per_km") val currentPaceSecondsPerKm: Int? = null,
    @SerialName("current_latitude") val currentLatitude: Double? = null,
    @SerialName("current_longitude") val currentLongitude: Double? = null,
)

fun RunEventDTO.toDomain(): RunEvent = RunEvent(
    id = id,
    createdBy = createdBy,
    title = title,
    description = description,
    mode = RunMode.valueOf(mode.uppercase()),
    visibility = visibility.toRunVisibility(),
    plannedStartAt = Instant.parse(plannedStartAt),
    plannedEndAt = plannedEndAt?.let(Instant::parse),
    checkInOpensAt = Instant.parse(checkInOpensAt),
    locationName = locationName,
    status = status.toRunEventStatus(),
    createdAt = Instant.parse(createdAt),
    updatedAt = Instant.parse(updatedAt),
)

fun RunEventParticipantDTO.toDomain(): RunEventParticipant = RunEventParticipant(
    id = id,
    eventId = eventId,
    userId = userId,
    role = RunParticipantRole.valueOf(role.uppercase()),
    status = status.toRunEventParticipantStatus(),
    invitedBy = invitedBy,
    invitedAt = invitedAt?.let(Instant::parse) ?: Instant.parse(createdAt),
    respondedAt = respondedAt?.let(Instant::parse),
    checkedInAt = checkedInAt?.let(Instant::parse),
    createdAt = Instant.parse(createdAt),
    updatedAt = Instant.parse(updatedAt),
)

fun LiveRunSessionDTO.toDomain(): LiveRunSession = LiveRunSession(
    id = id,
    sourceType = LiveRunSourceType.valueOf(sourceType.uppercase()),
    linkedEventId = linkedEventId,
    leaderUserId = leaderUserId,
    visibility = visibility.toRunVisibility(),
    mode = RunMode.valueOf(mode.uppercase()),
    state = LiveRunSessionState.valueOf(state.uppercase()),
    startedAt = Instant.parse(startedAt),
    cooldownStartedAt = cooldownStartedAt?.let(Instant::parse),
    endedAt = endedAt?.let(Instant::parse),
    lastActivityAt = Instant.parse(lastActivityAt),
    maxEndsAt = Instant.parse(maxEndsAt),
    createdAt = Instant.parse(createdAt),
    updatedAt = Instant.parse(updatedAt),
)

fun LiveRunParticipantDTO.toDomain(): LiveRunParticipant = LiveRunParticipant(
    id = id,
    sessionId = sessionId,
    userId = userId,
    status = status.toLiveRunParticipantStatus(),
    joinedAt = Instant.parse(joinedAt),
    becameActiveAt = becameActiveAt?.let(Instant::parse),
    finishedAt = finishedAt?.let(Instant::parse),
    leftAt = leftAt?.let(Instant::parse),
    isLeader = isLeader,
    createdAt = Instant.parse(createdAt),
    updatedAt = Instant.parse(updatedAt),
)

fun LiveRunPresenceDTO.toDomain(): LiveRunPresence = LiveRunPresence(
    id = id,
    sessionId = sessionId,
    userId = userId,
    state = RunPresenceState.valueOf(presenceState.uppercase()),
    lastSeenAt = Instant.parse(lastSeenAt),
    currentDistanceMeters = currentDistanceMeters,
    currentDurationSeconds = currentDurationSeconds.toLong(),
    currentPaceSecondsPerKm = currentPaceSecondsPerKm,
    currentLatitude = currentLatitude,
    currentLongitude = currentLongitude,
    updatedAt = Instant.parse(updatedAt),
)

private fun String.toRunVisibility(): RunVisibility = when (lowercase()) {
    "private" -> RunVisibility.PRIVATE
    "friends" -> RunVisibility.FRIENDS
    "invite_only" -> RunVisibility.INVITE_ONLY
    else -> error("Unknown RunVisibility value: $this")
}

private fun String.toRunEventStatus(): RunEventStatus = when (lowercase()) {
    "planned" -> RunEventStatus.PLANNED
    "check_in_open" -> RunEventStatus.CHECK_IN_OPEN
    "live" -> RunEventStatus.LIVE
    "completed" -> RunEventStatus.COMPLETED
    "cancelled" -> RunEventStatus.CANCELLED
    else -> error("Unknown RunEventStatus value: $this")
}

private fun String.toRunEventParticipantStatus(): RunParticipantStatus = when (lowercase()) {
    "invited" -> RunParticipantStatus.INVITED
    "accepted" -> RunParticipantStatus.ACCEPTED
    "declined" -> RunParticipantStatus.DECLINED
    "checked_in" -> RunParticipantStatus.CHECKED_IN
    else -> error("Unknown RunEventParticipantStatus value: $this")
}

private fun String.toLiveRunParticipantStatus(): RunParticipantStatus = when (lowercase()) {
    "invited" -> RunParticipantStatus.INVITED
    "joined" -> RunParticipantStatus.JOINED
    "active" -> RunParticipantStatus.ACTIVE
    "paused" -> RunParticipantStatus.PAUSED
    "finished" -> RunParticipantStatus.FINISHED
    "left" -> RunParticipantStatus.LEFT
    else -> error("Unknown LiveRunParticipantStatus value: $this")
}
