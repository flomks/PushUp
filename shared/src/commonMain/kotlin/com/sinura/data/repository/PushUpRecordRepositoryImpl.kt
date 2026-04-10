package com.sinura.data.repository

import com.sinura.data.mapper.toDomain
import com.sinura.db.SinuraDatabase
import com.sinura.domain.model.PushUpRecord
import com.sinura.domain.repository.PushUpRecordRepository
import kotlinx.coroutines.CoroutineDispatcher

/**
 * SQLDelight-backed implementation of [PushUpRecordRepository].
 *
 * Uses the generated query methods from `Database.sq` and the mappers
 * from [com.sinura.data.mapper] to convert between DB and domain models.
 *
 * All suspend functions are main-safe -- dispatcher switching is handled
 * by [safeDbCall].
 */
class PushUpRecordRepositoryImpl(
    private val database: SinuraDatabase,
    private val dispatcher: CoroutineDispatcher,
) : PushUpRecordRepository {

    private val queries get() = database.databaseQueries

    override suspend fun save(record: PushUpRecord): Unit = safeDbCall(
        dispatcher,
        "Failed to save push-up record '${record.id}'",
    ) {
        queries.insertPushUpRecord(
            id = record.id,
            sessionId = record.sessionId,
            timestamp = record.timestamp.toEpochMilliseconds(),
            durationMs = record.durationMs,
            depthScore = record.depthScore.toDouble(),
            formScore = record.formScore.toDouble(),
        )
    }

    override suspend fun saveAll(records: List<PushUpRecord>): Unit = safeDbCall(
        dispatcher,
        "Failed to save ${records.size} push-up records",
    ) {
        database.transaction {
            records.forEach { record ->
                queries.insertPushUpRecord(
                    id = record.id,
                    sessionId = record.sessionId,
                    timestamp = record.timestamp.toEpochMilliseconds(),
                    durationMs = record.durationMs,
                    depthScore = record.depthScore.toDouble(),
                    formScore = record.formScore.toDouble(),
                )
            }
        }
    }

    override suspend fun getBySessionId(sessionId: String): List<PushUpRecord> = safeDbCall(
        dispatcher,
        "Failed to get push-up records for session '$sessionId'",
    ) {
        queries.selectPushUpRecordsBySessionId(sessionId)
            .executeAsList()
            .map { it.toDomain() }
    }

    override suspend fun delete(id: String): Unit = safeDbCall(
        dispatcher,
        "Failed to delete push-up record '$id'",
    ) {
        queries.deletePushUpRecord(id)
    }
}
