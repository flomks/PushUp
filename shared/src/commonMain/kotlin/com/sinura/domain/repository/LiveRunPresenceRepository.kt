package com.sinura.domain.repository

import com.sinura.domain.model.LiveRunPresence
import kotlinx.coroutines.flow.Flow

interface LiveRunPresenceRepository {
    suspend fun upsert(presence: LiveRunPresence): LiveRunPresence
    suspend fun getForSession(sessionId: String): List<LiveRunPresence>
    suspend fun getForUser(sessionId: String, userId: String): LiveRunPresence?
    fun observeForSession(sessionId: String): Flow<List<LiveRunPresence>>
}
