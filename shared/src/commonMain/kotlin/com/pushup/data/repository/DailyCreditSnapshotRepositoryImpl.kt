package com.pushup.data.repository

import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.DailyCreditSnapshot
import com.pushup.domain.repository.DailyCreditSnapshotRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.datetime.LocalDate
import com.pushup.db.DailyCreditSnapshot as DbSnapshot

/**
 * SQLDelight-backed implementation of [DailyCreditSnapshotRepository].
 *
 * Snapshots are append-only (INSERT OR REPLACE keyed on userId + date).
 * All suspend functions are main-safe -- dispatcher switching is handled
 * by [safeDbCall].
 */
class DailyCreditSnapshotRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
) : DailyCreditSnapshotRepository {

    private val queries get() = database.databaseQueries

    override suspend fun save(snapshot: DailyCreditSnapshot): Unit = safeDbCall(
        dispatcher,
        "Failed to save daily credit snapshot for user '${snapshot.userId}' on ${snapshot.date}",
    ) {
        // Use "userId:date" as the deterministic row ID so INSERT OR REPLACE
        // is idempotent for the same user+date combination.
        val rowId = "${snapshot.userId}:${snapshot.date}"
        queries.insertOrReplaceDailyCreditSnapshot(
            id = rowId,
            userId = snapshot.userId,
            date = snapshot.date.toString(),
            earnedSeconds = snapshot.earnedSeconds,
            spentSeconds = snapshot.spentSeconds,
            carryOverSeconds = snapshot.carryOverSeconds,
            workoutEarnedSeconds = snapshot.workoutEarnedSeconds,
        )
    }

    override suspend fun getByDate(userId: String, date: LocalDate): DailyCreditSnapshot? = safeDbCall(
        dispatcher,
        "Failed to get daily credit snapshot for user '$userId' on $date",
    ) {
        queries.selectDailyCreditSnapshotByUserAndDate(userId, date.toString())
            .executeAsOneOrNull()
            ?.toDomain()
    }

    override suspend fun getByDateRange(
        userId: String,
        from: LocalDate,
        to: LocalDate,
    ): List<DailyCreditSnapshot> = safeDbCall(
        dispatcher,
        "Failed to get daily credit snapshots for user '$userId' from $from to $to",
    ) {
        queries.selectDailyCreditSnapshotsByDateRange(userId, from.toString(), to.toString())
            .executeAsList()
            .map { it.toDomain() }
    }
}

/**
 * Maps a SQLDelight [DbSnapshot] entity to a domain [DailyCreditSnapshot].
 */
private fun DbSnapshot.toDomain(): DailyCreditSnapshot = DailyCreditSnapshot(
    userId = userId,
    date = LocalDate.parse(date),
    earnedSeconds = earnedSeconds,
    spentSeconds = spentSeconds,
    carryOverSeconds = carryOverSeconds,
    workoutEarnedSeconds = workoutEarnedSeconds,
)
