package com.sinura.domain.repository

import com.sinura.domain.model.DailyCreditSnapshot
import kotlinx.datetime.LocalDate

/**
 * Repository for persisting and querying daily credit snapshots.
 *
 * Snapshots are written once per day by [com.sinura.domain.usecase.ApplyDailyResetUseCase]
 * and are never modified after creation (append-only).
 */
interface DailyCreditSnapshotRepository {

    /**
     * Persists a snapshot. Uses INSERT OR REPLACE so re-running the reset
     * for the same day is idempotent.
     */
    suspend fun save(snapshot: DailyCreditSnapshot)

    /**
     * Returns the snapshot for a specific [date], or `null` if none exists.
     */
    suspend fun getByDate(userId: String, date: LocalDate): DailyCreditSnapshot?

    /**
     * Returns all snapshots for [userId] whose date falls within [[from], [to]]
     * (both inclusive), ordered by date ascending.
     *
     * Used for building weekly/monthly charts.
     */
    suspend fun getByDateRange(
        userId: String,
        from: LocalDate,
        to: LocalDate,
    ): List<DailyCreditSnapshot>
}
