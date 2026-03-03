package com.pushup.data.repository

import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.PushUpRecord
import com.pushup.domain.repository.PushUpRecordRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext

/**
 * SQLDelight-backed implementation of [PushUpRecordRepository].
 *
 * Uses the generated query methods from `Database.sq` and the mappers
 * from [com.pushup.data.mapper] to convert between DB and domain models.
 *
 * All suspend functions switch to [dispatcher] to keep callers main-safe.
 *
 * @param database The SQLDelight-generated [PushUpDatabase] instance.
 * @param dispatcher The [CoroutineDispatcher] used for database I/O.
 */
class PushUpRecordRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
) : PushUpRecordRepository {

    private val queries get() = database.databaseQueries

    override suspend fun save(record: PushUpRecord): Unit = withContext(dispatcher) {
        try {
            queries.insertPushUpRecord(
                id = record.id,
                sessionId = record.sessionId,
                timestamp = record.timestamp.toEpochMilliseconds(),
                durationMs = record.durationMs,
                depthScore = record.depthScore.toDouble(),
                formScore = record.formScore.toDouble(),
            )
        } catch (e: Exception) {
            throw RepositoryException("Failed to save push-up record '${record.id}'", e)
        }
    }

    override suspend fun saveAll(records: List<PushUpRecord>): Unit = withContext(dispatcher) {
        try {
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
        } catch (e: Exception) {
            throw RepositoryException("Failed to save ${records.size} push-up records", e)
        }
    }

    override suspend fun getBySessionId(sessionId: String): List<PushUpRecord> =
        withContext(dispatcher) {
            try {
                queries.selectPushUpRecordsBySessionId(sessionId)
                    .executeAsList()
                    .map { it.toDomain() }
            } catch (e: Exception) {
                throw RepositoryException(
                    "Failed to get push-up records for session '$sessionId'",
                    e,
                )
            }
        }

    override suspend fun delete(id: String): Unit = withContext(dispatcher) {
        try {
            queries.deletePushUpRecord(id)
        } catch (e: Exception) {
            throw RepositoryException("Failed to delete push-up record '$id'", e)
        }
    }
}
