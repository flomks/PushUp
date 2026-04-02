package com.pushup.domain.model

import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.LocalDate
import kotlinx.datetime.minus
import kotlinx.datetime.plus

/**
 * Pure utility for streak calculation from a sorted list of distinct active dates.
 *
 * Extracted from [com.pushup.data.repository.StatsRepositoryImpl] so it can be
 * reused by both the push-up-only stats and the new unified activity stats
 * (which merges dates from all workout types).
 */
object StreakCalculator {

    /**
     * Calculates the current and longest streak from a sorted list of distinct
     * dates that had at least one activity.
     *
     * **Current streak** is only non-zero when the most recent date is either
     * [today] or yesterday. If the last activity was two or more days ago the
     * streak has been broken and `currentStreak` is `0`.
     *
     * @param sortedDates Distinct activity dates in ascending order.
     * @param today The reference date for "current" streak evaluation.
     * @return Pair of (currentStreak, longestStreak).
     */
    fun calculateStreaks(sortedDates: List<LocalDate>, today: LocalDate): Pair<Int, Int> {
        if (sortedDates.isEmpty()) return 0 to 0

        // Calculate longest streak by scanning consecutive runs
        var longestStreak = 1
        var runLength = 1

        for (i in 1 until sortedDates.size) {
            val expectedNext = sortedDates[i - 1].plus(1, DateTimeUnit.DAY)
            if (sortedDates[i] == expectedNext) {
                runLength++
                if (runLength > longestStreak) longestStreak = runLength
            } else {
                runLength = 1
            }
        }

        // Current streak: count backwards from the last date only if it is
        // today or yesterday. Otherwise the streak is already broken.
        val lastDate = sortedDates.last()
        val yesterday = today.minus(1, DateTimeUnit.DAY)
        val currentStreak = if (lastDate == today || lastDate == yesterday) {
            var streak = 1
            for (i in sortedDates.size - 1 downTo 1) {
                val expectedPrev = sortedDates[i].minus(1, DateTimeUnit.DAY)
                if (sortedDates[i - 1] == expectedPrev) {
                    streak++
                } else {
                    break
                }
            }
            streak
        } else {
            0
        }

        return currentStreak to longestStreak
    }
}
