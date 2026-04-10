package com.sinura.domain.repository

import com.sinura.domain.model.MonthlyActivitySummary

/**
 * Repository for querying unified activity statistics across all workout types.
 *
 * Unlike [StatsRepository], which is push-up-centric, this repository merges
 * data from every exercise type (push-ups, jogging, plank, etc.) into a single
 * activity view — suitable for heatmaps, streaks, and general activity stats.
 */
interface ActivityStatsRepository {

    /**
     * Returns a monthly activity summary containing one [com.sinura.domain.model.ActivityDayStats]
     * entry per calendar day (including zero-activity days), suitable for
     * rendering a heatmap grid.
     */
    suspend fun getMonthlyActivity(userId: String, month: Int, year: Int): MonthlyActivitySummary

    /**
     * Returns the unified activity streak (current, longest) calculated from
     * all workout types (push-ups AND jogging).
     *
     * @return Pair of (currentStreakDays, longestStreakDays).
     */
    suspend fun getActivityStreak(userId: String): Pair<Int, Int>
}
