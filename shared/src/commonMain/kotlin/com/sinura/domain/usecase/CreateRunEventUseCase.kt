package com.sinura.domain.usecase

import com.sinura.domain.model.RunEvent
import com.sinura.domain.model.RunEventParticipant
import com.sinura.domain.model.RunEventStatus
import com.sinura.domain.model.RunMode
import com.sinura.domain.model.RunParticipantRole
import com.sinura.domain.model.RunParticipantStatus
import com.sinura.domain.model.RunVisibility
import com.sinura.domain.repository.RunEventRepository
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

class CreateRunEventUseCase(
    private val repository: RunEventRepository,
    private val clock: Clock = Clock.System,
    private val idGenerator: IdGenerator = DefaultIdGenerator,
) {
    suspend operator fun invoke(
        organizerUserId: String,
        title: String,
        mode: RunMode,
        visibility: RunVisibility,
        plannedStartAt: Instant,
        invitedUserIds: List<String>,
        description: String? = null,
        plannedEndAt: Instant? = null,
        locationName: String? = null,
    ): RunEvent {
        require(organizerUserId.isNotBlank()) { "organizerUserId must not be blank" }
        require(title.isNotBlank()) { "title must not be blank" }

        val now = clock.now()
        val eventId = idGenerator.generate()
        val event = RunEvent(
            id = eventId,
            createdBy = organizerUserId,
            title = title.trim(),
            description = description?.trim()?.ifBlank { null },
            mode = mode,
            visibility = visibility,
            plannedStartAt = plannedStartAt,
            plannedEndAt = plannedEndAt,
            checkInOpensAt = Instant.fromEpochSeconds(plannedStartAt.epochSeconds - 30 * 60),
            locationName = locationName?.trim()?.ifBlank { null },
            status = RunEventStatus.PLANNED,
            createdAt = now,
            updatedAt = now,
        )

        val participants = buildList {
            add(
                RunEventParticipant(
                    id = idGenerator.generate(),
                    eventId = eventId,
                    userId = organizerUserId,
                    role = RunParticipantRole.ORGANIZER,
                    status = RunParticipantStatus.ACCEPTED,
                    invitedBy = null,
                    invitedAt = now,
                    respondedAt = now,
                    checkedInAt = null,
                    createdAt = now,
                    updatedAt = now,
                )
            )
            invitedUserIds
                .distinct()
                .filter { it.isNotBlank() && it != organizerUserId }
                .forEach { invitedUserId ->
                    add(
                        RunEventParticipant(
                            id = idGenerator.generate(),
                            eventId = eventId,
                            userId = invitedUserId,
                            role = RunParticipantRole.MEMBER,
                            status = RunParticipantStatus.INVITED,
                            invitedBy = organizerUserId,
                            invitedAt = now,
                            respondedAt = null,
                            checkedInAt = null,
                            createdAt = now,
                            updatedAt = now,
                        )
                    )
                }
        }

        return repository.create(event, participants)
    }
}
