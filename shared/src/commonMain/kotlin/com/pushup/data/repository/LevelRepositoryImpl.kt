package com.pushup.data.repository

import com.pushup.data.mapper.toDomain
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.LevelCalculator
import com.pushup.domain.model.UserLevel
import com.pushup.domain.repository.LevelRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.datetime.Clock

/**
 * SQLDelight-backed implementation of [LevelRepository].
 *
 * The [UserLevel] table stores only [totalXp]; the current level and progress
 * are derived on every read via [LevelCalculator.fromTotalXp].
 *
 * All suspend functions are main-safe -- dispatcher switching is handled
 * by [safeDbCall].
 *
 * @param database   The SQLDelight-generated [PushUpDatabase] instance.
 * @param dispatcher The [CoroutineDispatcher] used for database I/O.
 * @param clock      Clock used to set [lastUpdatedAt] timestamps.
 */
class LevelRepositoryImpl(
    private val database: PushUpDatabase,
    private val dispatcher: CoroutineDispatcher,
    private val clock: Clock = Clock.System,
) : LevelRepository {

    private val queries get() = database.databaseQueries

    override suspend fun get(userId: String): UserLevel? = safeDbCall(
        dispatcher,
        "Failed to get user level for user '$userId'",
    ) {
        queries.selectUserLevelByUserId(userId).executeAsOneOrNull()?.toDomain()
    }

    override suspend fun getOrCreate(userId: String): UserLevel = safeDbCall(
        dispatcher,
        "Failed to get or create user level for user '$userId'",
    ) {
        val existing = queries.selectUserLevelByUserId(userId).executeAsOneOrNull()
        if (existing != null) {
            existing.toDomain()
        } else {
            val now = clock.now().toEpochMilliseconds()
            queries.insertUserLevel(
                id = userId,
                userId = userId,
                totalXp = 0L,
                lastUpdatedAt = now,
            )
            UserLevel.initial(userId)
        }
    }

    override suspend fun addXp(userId: String, xpToAdd: Long): UserLevel {
        require(xpToAdd > 0) { "xpToAdd must be > 0, was $xpToAdd" }
        return safeDbCall(
            dispatcher,
            "Failed to add $xpToAdd XP for user '$userId'",
        ) {
            val now = clock.now().toEpochMilliseconds()
            var newTotalXp = 0L
            database.transaction {
                val existing = queries.selectUserLevelByUserId(userId).executeAsOneOrNull()
                if (existing != null) {
                    newTotalXp = existing.totalXp + xpToAdd
                    queries.updateUserLevelXp(
                        totalXp = newTotalXp,
                        lastUpdatedAt = now,
                        userId = userId,
                    )
                } else {
                    newTotalXp = xpToAdd
                    queries.insertUserLevel(
                        id = userId,
                        userId = userId,
                        totalXp = newTotalXp,
                        lastUpdatedAt = now,
                    )
                }
            }
            LevelCalculator.fromTotalXp(userId, newTotalXp)
        }
    }
}
