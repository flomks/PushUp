package com.pushup.domain.repository

import com.pushup.domain.model.RunEvent
import com.pushup.domain.model.RunEventParticipant
import com.pushup.domain.model.RunParticipantRole
import com.pushup.domain.model.RunParticipantStatus
import kotlinx.coroutines.flow.Flow

interface RunEventRepository {
    suspend fun create(event: RunEvent, participants: List<RunEventParticipant>): RunEvent
    suspend fun getById(eventId: String): RunEvent?
    suspend fun getUpcomingForUser(userId: String): List<RunEvent>
    suspend fun getParticipants(eventId: String): List<RunEventParticipant>
    suspend fun updateEventOrganizer(eventId: String, organizerUserId: String): RunEvent
    suspend fun updateParticipantRole(
        eventId: String,
        userId: String,
        role: RunParticipantRole,
    ): RunEventParticipant
    suspend fun updateParticipantStatus(
        eventId: String,
        userId: String,
        status: RunParticipantStatus,
    ): RunEventParticipant
    suspend fun removeParticipant(eventId: String, userId: String)
    suspend fun deleteEvent(eventId: String)
    fun observeUpcomingForUser(userId: String): Flow<List<RunEvent>>
}
