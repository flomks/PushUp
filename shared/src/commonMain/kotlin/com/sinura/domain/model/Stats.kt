package com.sinura.domain.model

import kotlinx.datetime.LocalDate
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

/**
 * Aggregated activity statistics for a single day.
 *
 * The primary metric is activity XP so different workout types can be compared
 * on one shared scale.
 */
@Serializable
data class DailyStats(
    val date: LocalDate,
    val totalActivityXp: Long,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageQuality: Float,
    val averageActivityXpPerSession: Float,
    val bestSessionActivityXp: Long,
) {
    init {
        require(totalActivityXp >= 0) { "DailyStats.totalActivityXp must be >= 0, was $totalActivityXp" }
        require(totalSessions >= 0) { "DailyStats.totalSessions must be >= 0, was $totalSessions" }
        require(totalEarnedSeconds >= 0) {
            "DailyStats.totalEarnedSeconds must be >= 0, was $totalEarnedSeconds"
        }
        require(averageQuality in 0f..1f) {
            "DailyStats.averageQuality must be in [0, 1], was $averageQuality"
        }
        require(averageActivityXpPerSession >= 0f) {
            "DailyStats.averageActivityXpPerSession must be >= 0, was $averageActivityXpPerSession"
        }
        require(bestSessionActivityXp >= 0) {
            "DailyStats.bestSessionActivityXp must be >= 0, was $bestSessionActivityXp"
        }
    }

    @Transient
    val hasActivity: Boolean = totalSessions > 0

    // Legacy aliases kept for bridge/UI compatibility during migration.
    @Transient
    val totalPushUps: Int = totalActivityXp.toInt()

    @Transient
    val averagePushUpsPerSession: Float = averageActivityXpPerSession

    @Transient
    val bestSession: Int = bestSessionActivityXp.toInt()
}

@Serializable
data class WeeklyStats(
    val weekStartDate: LocalDate,
    val totalActivityXp: Long,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageActivityXpPerSession: Float,
    val bestSessionActivityXp: Long,
    val dailyBreakdown: List<DailyStats>,
) {
    init {
        require(totalActivityXp >= 0) { "WeeklyStats.totalActivityXp must be >= 0, was $totalActivityXp" }
        require(totalSessions >= 0) { "WeeklyStats.totalSessions must be >= 0, was $totalSessions" }
        require(totalEarnedSeconds >= 0) {
            "WeeklyStats.totalEarnedSeconds must be >= 0, was $totalEarnedSeconds"
        }
        require(averageActivityXpPerSession >= 0f) {
            "WeeklyStats.averageActivityXpPerSession must be >= 0, was $averageActivityXpPerSession"
        }
        require(bestSessionActivityXp >= 0) {
            "WeeklyStats.bestSessionActivityXp must be >= 0, was $bestSessionActivityXp"
        }
    }

    @Transient
    val activeDays: Int = dailyBreakdown.count { it.hasActivity }

    @Transient
    val averageQuality: Float = dailyBreakdown
        .filter { it.hasActivity }
        .map { it.averageQuality }
        .average()
        .toFloat()
        .takeIf { !it.isNaN() } ?: 0f

    @Transient
    val totalPushUps: Int = totalActivityXp.toInt()

    @Transient
    val averagePushUpsPerSession: Float = averageActivityXpPerSession

    @Transient
    val bestSession: Int = bestSessionActivityXp.toInt()
}

@Serializable
data class MonthlyStats(
    val month: Int,
    val year: Int,
    val totalActivityXp: Long,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val averageActivityXpPerSession: Float,
    val bestSessionActivityXp: Long,
    val weeklyBreakdown: List<WeeklyStats>,
) {
    init {
        require(month in 1..12) { "MonthlyStats.month must be in [1, 12], was $month" }
        require(year > 0) { "MonthlyStats.year must be > 0, was $year" }
        require(totalActivityXp >= 0) { "MonthlyStats.totalActivityXp must be >= 0, was $totalActivityXp" }
        require(totalSessions >= 0) { "MonthlyStats.totalSessions must be >= 0, was $totalSessions" }
        require(totalEarnedSeconds >= 0) {
            "MonthlyStats.totalEarnedSeconds must be >= 0, was $totalEarnedSeconds"
        }
        require(averageActivityXpPerSession >= 0f) {
            "MonthlyStats.averageActivityXpPerSession must be >= 0, was $averageActivityXpPerSession"
        }
        require(bestSessionActivityXp >= 0) {
            "MonthlyStats.bestSessionActivityXp must be >= 0, was $bestSessionActivityXp"
        }
    }

    @Transient
    val activeWeeks: Int = weeklyBreakdown.count { it.totalSessions > 0 }

    @Transient
    val averageQuality: Float = weeklyBreakdown
        .filter { it.totalSessions > 0 }
        .map { it.averageQuality }
        .average()
        .toFloat()
        .takeIf { !it.isNaN() } ?: 0f

    @Transient
    val totalPushUps: Int = totalActivityXp.toInt()

    @Transient
    val averagePushUpsPerSession: Float = averageActivityXpPerSession

    @Transient
    val bestSession: Int = bestSessionActivityXp.toInt()
}

@Serializable
data class TotalStats(
    val userId: String,
    val totalActivityXp: Long,
    val totalSessions: Int,
    val totalEarnedSeconds: Long,
    val totalSpentSeconds: Long,
    val averageQuality: Float,
    val averageActivityXpPerSession: Float,
    val bestSessionActivityXp: Long,
    val currentStreakDays: Int,
    val longestStreakDays: Int,
) {
    init {
        require(userId.isNotBlank()) { "TotalStats.userId must not be blank" }
        require(totalActivityXp >= 0) { "TotalStats.totalActivityXp must be >= 0, was $totalActivityXp" }
        require(totalSessions >= 0) { "TotalStats.totalSessions must be >= 0, was $totalSessions" }
        require(totalEarnedSeconds >= 0) {
            "TotalStats.totalEarnedSeconds must be >= 0, was $totalEarnedSeconds"
        }
        require(totalSpentSeconds >= 0) {
            "TotalStats.totalSpentSeconds must be >= 0, was $totalSpentSeconds"
        }
        require(averageQuality in 0f..1f) {
            "TotalStats.averageQuality must be in [0, 1], was $averageQuality"
        }
        require(averageActivityXpPerSession >= 0f) {
            "TotalStats.averageActivityXpPerSession must be >= 0, was $averageActivityXpPerSession"
        }
        require(bestSessionActivityXp >= 0) {
            "TotalStats.bestSessionActivityXp must be >= 0, was $bestSessionActivityXp"
        }
        require(currentStreakDays >= 0) {
            "TotalStats.currentStreakDays must be >= 0, was $currentStreakDays"
        }
        require(longestStreakDays >= 0) {
            "TotalStats.longestStreakDays must be >= 0, was $longestStreakDays"
        }
        require(longestStreakDays >= currentStreakDays) {
            "TotalStats.longestStreakDays ($longestStreakDays) must be >= currentStreakDays ($currentStreakDays)"
        }
    }

    @Transient
    val availableSeconds: Long = totalEarnedSeconds - totalSpentSeconds

    @Transient
    val totalPushUps: Int = totalActivityXp.toInt()

    @Transient
    val averagePushUpsPerSession: Float = averageActivityXpPerSession

    @Transient
    val bestSession: Int = bestSessionActivityXp.toInt()
}
