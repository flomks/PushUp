package com.pushup.service

import com.pushup.dto.StatsPeriod
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Unit tests for [FriendActivityStatsService] pure helper logic.
 *
 * The [FriendActivityStatsService.dateRangeFor] method is a pure function
 * (no DB access) and is therefore straightforward to test without any
 * database setup.
 */
class FriendActivityStatsServiceTest {

    private val service = FriendActivityStatsService()

    // -----------------------------------------------------------------------
    // dateRangeFor -- day
    // -----------------------------------------------------------------------

    @Test
    fun `day period returns today to today`() {
        val today = LocalDate.of(2026, 3, 9)
        val (from, to) = service.dateRangeFor(StatsPeriod.day, today)
        assertEquals(today, from)
        assertEquals(today, to)
    }

    @Test
    fun `day period from equals to`() {
        val today = LocalDate.of(2026, 1, 1)
        val (from, to) = service.dateRangeFor(StatsPeriod.day, today)
        assertEquals(from, to)
    }

    // -----------------------------------------------------------------------
    // dateRangeFor -- week
    // -----------------------------------------------------------------------

    @Test
    fun `week period starts on Monday and ends on Sunday`() {
        // 2026-03-09 is a Monday
        val monday = LocalDate.of(2026, 3, 9)
        val (from, to) = service.dateRangeFor(StatsPeriod.week, monday)
        assertEquals(LocalDate.of(2026, 3, 9), from)
        assertEquals(LocalDate.of(2026, 3, 15), to)
    }

    @Test
    fun `week period from a Wednesday returns the enclosing Monday to Sunday`() {
        // 2026-03-11 is a Wednesday
        val wednesday = LocalDate.of(2026, 3, 11)
        val (from, to) = service.dateRangeFor(StatsPeriod.week, wednesday)
        assertEquals(LocalDate.of(2026, 3, 9), from)   // Monday
        assertEquals(LocalDate.of(2026, 3, 15), to)    // Sunday
    }

    @Test
    fun `week period from a Sunday returns the enclosing Monday to Sunday`() {
        // 2026-03-15 is a Sunday
        val sunday = LocalDate.of(2026, 3, 15)
        val (from, to) = service.dateRangeFor(StatsPeriod.week, sunday)
        assertEquals(LocalDate.of(2026, 3, 9), from)   // Monday
        assertEquals(LocalDate.of(2026, 3, 15), to)    // Sunday
    }

    @Test
    fun `week period spans exactly 7 days`() {
        val today = LocalDate.of(2026, 3, 11)
        val (from, to) = service.dateRangeFor(StatsPeriod.week, today)
        assertEquals(6, java.time.temporal.ChronoUnit.DAYS.between(from, to))
    }

    @Test
    fun `week period spanning month boundary is correct`() {
        // 2026-03-30 is a Monday; week ends on 2026-04-05 (Sunday)
        val monday = LocalDate.of(2026, 3, 30)
        val (from, to) = service.dateRangeFor(StatsPeriod.week, monday)
        assertEquals(LocalDate.of(2026, 3, 30), from)
        assertEquals(LocalDate.of(2026, 4, 5), to)
    }

    // -----------------------------------------------------------------------
    // dateRangeFor -- month
    // -----------------------------------------------------------------------

    @Test
    fun `month period returns first and last day of the month`() {
        val today = LocalDate.of(2026, 3, 9)
        val (from, to) = service.dateRangeFor(StatsPeriod.month, today)
        assertEquals(LocalDate.of(2026, 3, 1), from)
        assertEquals(LocalDate.of(2026, 3, 31), to)
    }

    @Test
    fun `month period for February in a non-leap year ends on 28th`() {
        val today = LocalDate.of(2026, 2, 15)
        val (from, to) = service.dateRangeFor(StatsPeriod.month, today)
        assertEquals(LocalDate.of(2026, 2, 1), from)
        assertEquals(LocalDate.of(2026, 2, 28), to)
    }

    @Test
    fun `month period for February in a leap year ends on 29th`() {
        val today = LocalDate.of(2024, 2, 10)
        val (from, to) = service.dateRangeFor(StatsPeriod.month, today)
        assertEquals(LocalDate.of(2024, 2, 1), from)
        assertEquals(LocalDate.of(2024, 2, 29), to)
    }

    @Test
    fun `month period for April ends on 30th`() {
        val today = LocalDate.of(2026, 4, 1)
        val (from, to) = service.dateRangeFor(StatsPeriod.month, today)
        assertEquals(LocalDate.of(2026, 4, 1), from)
        assertEquals(LocalDate.of(2026, 4, 30), to)
    }

    @Test
    fun `month period from the first day of the month`() {
        val firstDay = LocalDate.of(2026, 3, 1)
        val (from, to) = service.dateRangeFor(StatsPeriod.month, firstDay)
        assertEquals(LocalDate.of(2026, 3, 1), from)
        assertEquals(LocalDate.of(2026, 3, 31), to)
    }

    @Test
    fun `month period from the last day of the month`() {
        val lastDay = LocalDate.of(2026, 3, 31)
        val (from, to) = service.dateRangeFor(StatsPeriod.month, lastDay)
        assertEquals(LocalDate.of(2026, 3, 1), from)
        assertEquals(LocalDate.of(2026, 3, 31), to)
    }

    // -----------------------------------------------------------------------
    // StatsPeriod.fromQueryParam
    // -----------------------------------------------------------------------

    @Test
    fun `fromQueryParam returns day for lowercase day`() {
        assertEquals(StatsPeriod.day, StatsPeriod.fromQueryParam("day"))
    }

    @Test
    fun `fromQueryParam returns week for lowercase week`() {
        assertEquals(StatsPeriod.week, StatsPeriod.fromQueryParam("week"))
    }

    @Test
    fun `fromQueryParam returns month for lowercase month`() {
        assertEquals(StatsPeriod.month, StatsPeriod.fromQueryParam("month"))
    }

    @Test
    fun `fromQueryParam is case-insensitive`() {
        assertEquals(StatsPeriod.day,   StatsPeriod.fromQueryParam("DAY"))
        assertEquals(StatsPeriod.week,  StatsPeriod.fromQueryParam("WEEK"))
        assertEquals(StatsPeriod.month, StatsPeriod.fromQueryParam("MONTH"))
    }

    @Test
    fun `fromQueryParam returns null for unknown value`() {
        assertEquals(null, StatsPeriod.fromQueryParam("year"))
        assertEquals(null, StatsPeriod.fromQueryParam(""))
        assertEquals(null, StatsPeriod.fromQueryParam(null))
        assertEquals(null, StatsPeriod.fromQueryParam("daily"))
    }
}
