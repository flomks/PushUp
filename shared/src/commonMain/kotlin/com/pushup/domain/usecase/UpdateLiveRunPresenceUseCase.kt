package com.pushup.domain.usecase

import com.pushup.domain.model.LiveRunPresence
import com.pushup.domain.model.RunPresenceState
import com.pushup.domain.repository.LiveRunPresenceRepository
import kotlinx.datetime.Clock

class UpdateLiveRunPresenceUseCase(
    private val repository: LiveRunPresenceRepository,
    private val clock: Clock = Clock.System,
    private val idGenerator: IdGenerator = DefaultIdGenerator,
) {
    suspend operator fun invoke(
        sessionId: String,
        userId: String,
        state: RunPresenceState,
        distanceMeters: Double,
        durationSeconds: Long,
        paceSecondsPerKm: Int?,
        latitude: Double? = null,
        longitude: Double? = null,
    ): LiveRunPresence {
        require(sessionId.isNotBlank()) { "sessionId must not be blank" }
        require(userId.isNotBlank()) { "userId must not be blank" }

        val now = clock.now()
        val existing = repository.getForUser(sessionId, userId)
        val presence = existing?.copy(
            state = state,
            lastSeenAt = now,
            currentDistanceMeters = distanceMeters,
            currentDurationSeconds = durationSeconds,
            currentPaceSecondsPerKm = paceSecondsPerKm,
            currentLatitude = latitude,
            currentLongitude = longitude,
            updatedAt = now,
        ) ?: LiveRunPresence(
            id = idGenerator.generate(),
            sessionId = sessionId,
            userId = userId,
            state = state,
            lastSeenAt = now,
            currentDistanceMeters = distanceMeters,
            currentDurationSeconds = durationSeconds,
            currentPaceSecondsPerKm = paceSecondsPerKm,
            currentLatitude = latitude,
            currentLongitude = longitude,
            updatedAt = now,
        )

        return repository.upsert(presence)
    }
}
