package com.sinura.domain.repository

import com.sinura.domain.model.PushUpRecord

/**
 * Repository for managing [PushUpRecord] entities.
 *
 * Push-up records are always associated with a parent [com.sinura.domain.model.WorkoutSession].
 *
 * Implementations must be **main-safe** -- all dispatcher switching is handled internally.
 */
interface PushUpRecordRepository {

    /**
     * Persists a single [record] to the data store.
     *
     * @param record The push-up record to save.
     */
    suspend fun save(record: PushUpRecord)

    /**
     * Persists multiple [records] to the data store in a single transaction.
     *
     * @param records The push-up records to save.
     */
    suspend fun saveAll(records: List<PushUpRecord>)

    /**
     * Retrieves all push-up records belonging to the given [sessionId],
     * ordered by [PushUpRecord.timestamp] ascending.
     *
     * @param sessionId The session whose records to retrieve.
     * @return A list of all records for the session, possibly empty.
     */
    suspend fun getBySessionId(sessionId: String): List<PushUpRecord>

    /**
     * Deletes the push-up record with the given [id] from the data store.
     *
     * @param id The unique identifier of the record to delete.
     */
    suspend fun delete(id: String)
}
