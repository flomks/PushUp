package com.sinura.domain.model

/**
 * Intensity level for a single day in the activity heatmap.
 *
 * Mirrors the GitHub contribution graph approach: five discrete levels
 * from no activity to maximum activity. The UI maps each level to a
 * progressively stronger colour (e.g. deeper green or higher opacity).
 */
enum class HeatmapIntensity {
    /** No activity on this day. */
    NONE,
    /** 1-25 % of the user's reference maximum. */
    LOW,
    /** 26-50 % of the user's reference maximum. */
    MEDIUM,
    /** 51-75 % of the user's reference maximum. */
    HIGH,
    /** 76-100 %+ of the user's reference maximum. */
    MAX,
}

/**
 * Pure-function utilities for mapping raw activity data to [HeatmapIntensity] levels.
 *
 * The **reference maximum** is the user's 90th-percentile active day within
 * the displayed time window. This makes the heatmap self-calibrating:
 * light users get meaningful colour variation without hard-coded thresholds,
 * and heavy users are not stuck at "MAX" every day.
 */
object HeatmapCalculator {

    /** Minimum reference max to avoid division-by-zero or overly sensitive grids. */
    private const val MIN_REFERENCE_MAX_SECONDS = 60L // 1 minute

    /**
     * Computes the reference maximum for a set of days.
     *
     * Returns the 90th-percentile of non-zero [ActivityDayStats.totalEarnedSeconds]
     * values. If fewer than 5 active days exist, falls back to the absolute
     * maximum (or [MIN_REFERENCE_MAX_SECONDS] as a floor).
     */
    fun calculateReferenceMax(days: List<ActivityDayStats>): Long {
        val activeDays = days
            .filter { it.totalEarnedSeconds > 0 }
            .map { it.totalEarnedSeconds }
            .sorted()

        if (activeDays.isEmpty()) return MIN_REFERENCE_MAX_SECONDS

        // Fewer than 5 active days → use absolute max
        if (activeDays.size < 5) {
            return activeDays.last().coerceAtLeast(MIN_REFERENCE_MAX_SECONDS)
        }

        // 90th percentile (index = ceil(0.9 * n) - 1)
        val index = ((activeDays.size * 0.9).toInt()).coerceAtMost(activeDays.size - 1)
        return activeDays[index].coerceAtLeast(MIN_REFERENCE_MAX_SECONDS)
    }

    /**
     * Maps a single day's earned seconds to a [HeatmapIntensity] level
     * relative to the given [referenceMax].
     */
    fun calculateIntensity(earnedSeconds: Long, referenceMax: Long): HeatmapIntensity {
        if (earnedSeconds <= 0) return HeatmapIntensity.NONE

        val safeMax = referenceMax.coerceAtLeast(MIN_REFERENCE_MAX_SECONDS)
        val ratio = earnedSeconds.toDouble() / safeMax

        return when {
            ratio <= 0.25 -> HeatmapIntensity.LOW
            ratio <= 0.50 -> HeatmapIntensity.MEDIUM
            ratio <= 0.75 -> HeatmapIntensity.HIGH
            else -> HeatmapIntensity.MAX
        }
    }
}
