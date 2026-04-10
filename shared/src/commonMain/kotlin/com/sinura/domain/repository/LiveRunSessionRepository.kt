package com.sinura.domain.repository

import com.sinura.domain.model.LiveRunParticipant
import com.sinura.domain.model.LiveRunSession
import com.sinura.domain.model.LiveRunSessionState
import kotlinx.coroutines.flow.Flow

interface LiveRunSessionRepository {
    suspend fun create(session: LiveRunSession, leader: LiveRunParticipant): LiveRunSession
    suspend fun getById(sessionId: String): LiveRunSession?
    suspend fun getParticipants(sessionId: String): List<LiveRunParticipant>
    suspend fun upsertParticipant(participant: LiveRunParticipant): LiveRunParticipant
    suspend fun updateLeader(sessionId: String, newLeaderUserId: String): LiveRunSession
    suspend fun updateState(sessionId: String, state: LiveRunSessionState): LiveRunSession
    suspend fun getFriendsActiveSessions(userId: String): List<LiveRunSession>
    fun observeSession(sessionId: String): Flow<LiveRunSession?>
    fun observeParticipants(sessionId: String): Flow<List<LiveRunParticipant>>
}
