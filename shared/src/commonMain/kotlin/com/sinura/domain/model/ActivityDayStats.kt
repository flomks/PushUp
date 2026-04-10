package com.sinura.domain.model

import kotlinx.datetime.LocalDate
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

/**
 * Aggregated activity statistics for a single day across all workout types.
 *
 * Unlike [DailyStats], which is push-up-centric, this model captures
 * activity from every exercise type (push-ups, jogging, plank, etc.).
 *
 * @property date The calendar date these stats cover.
 * @property totalSessions Total number of completed sessions (all workout types).
 * @property totalEarnedSeconds Total screen-time credits earned on this day (in seconds).
 *   This serves as the universal "activity score" since every workout type earns credits.
 * @property workoutTypes The set of exercise types performed on this day.
 */
@Serializable
data class ActivityDayStats(
    val date: LocalDate,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val workoutTypes: Set<ExerciseType>,
) {
    init {
        require(totalSessions >= 0) { "ActivityDayStats.totalSessions must be >= 0, was $totalSessions" }
        require(totalEarnedSeconds >= 0) {
            "ActivityDayStats.totalEarnedSeconds must be >= 0, was $totalEarnedSeconds"
        }
    }

    /** `true` when at least one session was completed on this day. */
    @Transient
    val hasActivity: Boolean = totalSessions > 0
}
