package com.sinura.domain.usecase

import com.sinura.domain.model.LiveRunParticipant
import com.sinura.domain.model.LiveRunSession
import com.sinura.domain.model.LiveRunSessionState
import com.sinura.domain.model.RunEventParticipant
import com.sinura.domain.model.RunParticipantStatus
import com.sinura.domain.model.RunXpBonusType
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlin.math.roundToLong

data class RunXpBonusDecision(
    val type: RunXpBonusType,
    val multiplier: Double,
) {
    fun apply(baseXp: Long): Long = (baseXp.toDouble() * multiplier).roundToLong()
}

object RunXpBonusCalculator {
    const val CREW_MIN_OVERLAP_SECONDS: Long = 5 * 60
    const val SYNCED_MIN_OVERLAP_SECONDS: Long = 15 * 60
    const val SYNCED_START_WINDOW_SECONDS: Long = 10 * 60

    fun evaluate(
        participant: LiveRunParticipant,
        others: List<LiveRunParticipant>,
    ): RunXpBonusDecision {
        val peers = others.filter { it.userId != participant.userId }
        if (peers.isEmpty()) return RunXpBonusDecision(RunXpBonusType.SOLO, 1.0)

        val qualifiesForCrew = peers.any { overlapSeconds(participant, it) >= CREW_MIN_OVERLAP_SECONDS }
        if (!qualifiesForCrew) return RunXpBonusDecision(RunXpBonusType.SOLO, 1.0)

        val qualifiesForSynced = peers.any { other ->
            overlapSeconds(participant, other) >= SYNCED_MIN_OVERLAP_SECONDS &&
                startGapSeconds(participant, other) <= SYNCED_START_WINDOW_SECONDS
        }

        return if (qualifiesForSynced) {
            RunXpBonusDecision(RunXpBonusType.SYNCED, 1.2)
        } else {
            RunXpBonusDecision(RunXpBonusType.CREW, 1.1)
        }
    }

    private fun overlapSeconds(a: LiveRunParticipant, b: LiveRunParticipant): Long {
        val aStart = a.becameActiveAt ?: a.joinedAt
        val bStart = b.becameActiveAt ?: b.joinedAt
        val aEnd = a.finishedAt ?: a.leftAt ?: a.updatedAt
        val bEnd = b.finishedAt ?: b.leftAt ?: b.updatedAt
        val start = maxOf(aStart, bStart)
        val end = minOf(aEnd, bEnd)
        return (end.epochSeconds - start.epochSeconds).coerceAtLeast(0)
    }

    private fun startGapSeconds(a: LiveRunParticipant, b: LiveRunParticipant): Long {
        val aStart = a.becameActiveAt ?: a.joinedAt
        val bStart = b.becameActiveAt ?: b.joinedAt
        return kotlin.math.abs(aStart.epochSeconds - bStart.epochSeconds)
    }
}

object LeaderSelectionPolicy {
    fun selectNextLeader(
        participants: List<LiveRunParticipant>,
        organizerUserId: String? = null,
    ): LiveRunParticipant? {
        val active = participants.filter {
            it.status == RunParticipantStatus.ACTIVE ||
                it.status == RunParticipantStatus.JOINED ||
                it.status == RunParticipantStatus.PAUSED
        }
        if (active.isEmpty()) return null

        organizerUserId?.let { organizerId ->
            active.firstOrNull { it.userId == organizerId }?.let { return it }
        }

        return active.minByOrNull { it.joinedAt.epochSeconds }
    }
}

object EventOrganizerSelectionPolicy {
    fun selectNextOrganizer(
        participants: List<RunEventParticipant>,
    ): RunEventParticipant? =
        participants.minByOrNull { participant ->
            participant.respondedAt?.epochSeconds
                ?: participant.checkedInAt?.epochSeconds
                ?: participant.invitedAt.epochSeconds
        }
}

object LiveRunLifecyclePolicy {
    const val DEFAULT_COOLDOWN_SECONDS: Long = 10 * 60
    const val DEFAULT_MAX_SESSION_SECONDS: Long = 6 * 60 * 60

    fun initialMaxEndAt(startedAt: Instant): Instant =
        Instant.fromEpochSeconds(startedAt.epochSeconds + DEFAULT_MAX_SESSION_SECONDS)

    fun shouldEnterCooldown(activeParticipants: List<LiveRunParticipant>): Boolean =
        activeParticipants.none { it.status == RunParticipantStatus.ACTIVE }

    fun nextStateAfterFinish(
        session: LiveRunSession,
        activeParticipants: List<LiveRunParticipant>,
    ): LiveRunSessionState =
        if (session.state == LiveRunSessionState.FINISHED) LiveRunSessionState.FINISHED
        else if (shouldEnterCooldown(activeParticipants)) LiveRunSessionState.COOLDOWN
        else LiveRunSessionState.LIVE

    fun cooldownExpired(
        session: LiveRunSession,
        now: Instant = Clock.System.now(),
    ): Boolean {
        val cooldownStartedAt = session.cooldownStartedAt ?: return false
        return now.epochSeconds - cooldownStartedAt.epochSeconds >= DEFAULT_COOLDOWN_SECONDS
    }
}
