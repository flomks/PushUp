package com.pushup.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

@Serializable
enum class RunMode { RECOVERY, BASE, TEMPO, LONG_RUN, RACE }

@Serializable
enum class RunVisibility { PRIVATE, FRIENDS, INVITE_ONLY }

@Serializable
enum class RunEventStatus { PLANNED, CHECK_IN_OPEN, LIVE, COMPLETED, CANCELLED }

@Serializable
enum class LiveRunSourceType { PLANNED, SPONTANEOUS }

@Serializable
enum class LiveRunSessionState { LIVE, COOLDOWN, FINISHED }

@Serializable
enum class RunParticipantRole { ORGANIZER, MEMBER }

@Serializable
enum class RunParticipantStatus { INVITED, ACCEPTED, DECLINED, CHECKED_IN, JOINED, ACTIVE, PAUSED, FINISHED, LEFT }

@Serializable
enum class RunPresenceState { ACTIVE, PAUSED, DISCONNECTED, FINISHED }

@Serializable
enum class RunXpBonusType { SOLO, CREW, SYNCED }

@Serializable
data class RunEvent(
    val id: String,
    val createdBy: String,
    val title: String,
    val description: String?,
    val mode: RunMode,
    val visibility: RunVisibility,
    val plannedStartAt: Instant,
    val plannedEndAt: Instant?,
    val checkInOpensAt: Instant,
    val locationName: String?,
    val status: RunEventStatus,
    val createdAt: Instant,
    val updatedAt: Instant,
) {
    init {
        require(id.isNotBlank()) { "RunEvent.id must not be blank" }
        require(createdBy.isNotBlank()) { "RunEvent.createdBy must not be blank" }
        require(title.isNotBlank()) { "RunEvent.title must not be blank" }
        plannedEndAt?.let { end ->
            require(end >= plannedStartAt) {
                "RunEvent.plannedEndAt ($end) must not precede plannedStartAt ($plannedStartAt)"
            }
        }
        require(checkInOpensAt <= plannedStartAt) {
            "RunEvent.checkInOpensAt ($checkInOpensAt) must be <= plannedStartAt ($plannedStartAt)"
        }
        require(updatedAt >= createdAt) {
            "RunEvent.updatedAt ($updatedAt) must be >= createdAt ($createdAt)"
        }
    }
}

@Serializable
data class RunEventParticipant(
    val id: String,
    val eventId: String,
    val userId: String,
    val role: RunParticipantRole,
    val status: RunParticipantStatus,
    val invitedBy: String?,
    val invitedAt: Instant,
    val respondedAt: Instant?,
    val checkedInAt: Instant?,
    val createdAt: Instant,
    val updatedAt: Instant,
) {
    init {
        require(id.isNotBlank()) { "RunEventParticipant.id must not be blank" }
        require(eventId.isNotBlank()) { "RunEventParticipant.eventId must not be blank" }
        require(userId.isNotBlank()) { "RunEventParticipant.userId must not be blank" }
        require(updatedAt >= createdAt) {
            "RunEventParticipant.updatedAt ($updatedAt) must be >= createdAt ($createdAt)"
        }
    }
}

@Serializable
data class LiveRunSession(
    val id: String,
    val sourceType: LiveRunSourceType,
    val linkedEventId: String?,
    val leaderUserId: String,
    val visibility: RunVisibility,
    val mode: RunMode,
    val state: LiveRunSessionState,
    val startedAt: Instant,
    val cooldownStartedAt: Instant?,
    val endedAt: Instant?,
    val lastActivityAt: Instant,
    val maxEndsAt: Instant,
    val createdAt: Instant,
    val updatedAt: Instant,
) {
    init {
        require(id.isNotBlank()) { "LiveRunSession.id must not be blank" }
        require(leaderUserId.isNotBlank()) { "LiveRunSession.leaderUserId must not be blank" }
        require(lastActivityAt >= startedAt) {
            "LiveRunSession.lastActivityAt ($lastActivityAt) must be >= startedAt ($startedAt)"
        }
        require(maxEndsAt >= startedAt) {
            "LiveRunSession.maxEndsAt ($maxEndsAt) must be >= startedAt ($startedAt)"
        }
        require(updatedAt >= createdAt) {
            "LiveRunSession.updatedAt ($updatedAt) must be >= createdAt ($createdAt)"
        }
    }
}

@Serializable
data class LiveRunParticipant(
    val id: String,
    val sessionId: String,
    val userId: String,
    val status: RunParticipantStatus,
    val joinedAt: Instant,
    val becameActiveAt: Instant?,
    val finishedAt: Instant?,
    val leftAt: Instant?,
    val isLeader: Boolean,
    val createdAt: Instant,
    val updatedAt: Instant,
) {
    init {
        require(id.isNotBlank()) { "LiveRunParticipant.id must not be blank" }
        require(sessionId.isNotBlank()) { "LiveRunParticipant.sessionId must not be blank" }
        require(userId.isNotBlank()) { "LiveRunParticipant.userId must not be blank" }
        require(updatedAt >= createdAt) {
            "LiveRunParticipant.updatedAt ($updatedAt) must be >= createdAt ($createdAt)"
        }
    }
}

@Serializable
data class LiveRunPresence(
    val id: String,
    val sessionId: String,
    val userId: String,
    val state: RunPresenceState,
    val lastSeenAt: Instant,
    val currentDistanceMeters: Double,
    val currentDurationSeconds: Long,
    val currentPaceSecondsPerKm: Int?,
    val currentLatitude: Double?,
    val currentLongitude: Double?,
    val updatedAt: Instant,
) {
    init {
        require(id.isNotBlank()) { "LiveRunPresence.id must not be blank" }
        require(sessionId.isNotBlank()) { "LiveRunPresence.sessionId must not be blank" }
        require(userId.isNotBlank()) { "LiveRunPresence.userId must not be blank" }
        require(currentDistanceMeters >= 0.0) {
            "LiveRunPresence.currentDistanceMeters must be >= 0, was $currentDistanceMeters"
        }
        require(currentDurationSeconds >= 0L) {
            "LiveRunPresence.currentDurationSeconds must be >= 0, was $currentDurationSeconds"
        }
    }
}

@Serializable
data class RunXpAward(
    val id: String,
    val userId: String,
    val sessionId: String,
    val baseXp: Long,
    val bonusType: RunXpBonusType,
    val bonusMultiplier: Double,
    val bonusXp: Long,
    val totalXpAwarded: Long,
    val awardedAt: Instant,
) {
    init {
        require(id.isNotBlank()) { "RunXpAward.id must not be blank" }
        require(userId.isNotBlank()) { "RunXpAward.userId must not be blank" }
        require(sessionId.isNotBlank()) { "RunXpAward.sessionId must not be blank" }
        require(baseXp >= 0L) { "RunXpAward.baseXp must be >= 0, was $baseXp" }
        require(bonusMultiplier >= 1.0) {
            "RunXpAward.bonusMultiplier must be >= 1.0, was $bonusMultiplier"
        }
        require(bonusXp >= 0L) { "RunXpAward.bonusXp must be >= 0, was $bonusXp" }
        require(totalXpAwarded >= 0L) {
            "RunXpAward.totalXpAwarded must be >= 0, was $totalXpAwarded"
        }
    }
}
