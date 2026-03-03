package com.pushup.domain.repository

import com.pushup.domain.model.DailyStats
import com.pushup.domain.model.MonthlyStats
import com.pushup.domain.model.TotalStats
import com.pushup.domain.model.WeeklyStats
import kotlinx.datetime.LocalDate

/**
 * Repository for retrieving aggregated workout statistics.
 *
 * All methods are read-only. Statistics are computed from persisted workout
 * and push-up data covering various time granularities (day, week, month, lifetime).
 *
 * Implementations must be **main-safe** -- all dispatcher switching is handled internally.
 */
interface StatsRepository {

    /**
     * Retrieves aggregated statistics for a specific day.
     *
     * @param userId The user whose stats to retrieve.
     * @param date The calendar date to aggregate.
     * @return The daily statistics, or `null` if no data exists for that day.
     */
    suspend fun getDailyStats(userId: String, date: LocalDate): DailyStats?

    /**
     * Retrieves aggregated statistics for a specific week.
     *
     * @param userId The user whose stats to retrieve.
     * @param weekStart The first day (typically Monday) of the week to aggregate.
     * @return The weekly statistics, or `null` if no data exists for that week.
     */
    suspend fun getWeeklyStats(userId: String, weekStart: LocalDate): WeeklyStats?

    /**
     * Retrieves aggregated statistics for a specific month.
     *
     * @param userId The user whose stats to retrieve.
     * @param month The month number (1-12).
     * @param year The four-digit year.
     * @return The monthly statistics, or `null` if no data exists for that month.
     */
    suspend fun getMonthlyStats(userId: String, month: Int, year: Int): MonthlyStats?

    /**
     * Retrieves lifetime aggregated statistics for a user (since app installation).
     *
     * @param userId The user whose total stats to retrieve.
     * @return The total lifetime statistics, or `null` if the user has no data.
     */
    suspend fun getTotalStats(userId: String): TotalStats?
}
