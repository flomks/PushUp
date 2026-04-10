package com.sinura.domain.repository

import com.sinura.domain.model.RunXpAward

interface RunXpAwardRepository {
    suspend fun save(award: RunXpAward): RunXpAward
    suspend fun getBySessionIdAndUserId(sessionId: String, userId: String): RunXpAward?
    suspend fun getBySessionId(sessionId: String): List<RunXpAward>
    suspend fun getByUserId(userId: String): List<RunXpAward>
}
