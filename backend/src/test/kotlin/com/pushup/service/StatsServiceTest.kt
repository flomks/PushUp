package com.pushup.service

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Unit tests for [StatsService] streak calculation logic.
 *
 * The streak helpers are pure functions (no DB access) and are therefore
 * straightforward to test without any database setup.
 */
class StatsServiceTest {

    private val service = StatsService()

    // -----------------------------------------------------------------------
    // calculateCurrentStreak
    // -----------------------------------------------------------------------

    @Test
    fun `currentStreak is 0 when no workout days`() {
        val today = LocalDate.of(2026, 3, 3)
        val result = service.calculateCurrentStreak(emptyList(), today)
        assertEquals(0, result)
    }

    @Test
    fun `currentStreak is 1 when only today has a workout`() {
        val today = LocalDate.of(2026, 3, 3)
        val workoutDays = listOf(today)
        val result = service.calculateCurrentStreak(workoutDays, today)
        assertEquals(1, result)
    }

    @Test
    fun `currentStreak is 1 when only yesterday has a workout`() {
        val today = LocalDate.of(2026, 3, 3)
        val yesterday = today.minusDays(1)
        val workoutDays = listOf(yesterday)
        val result = service.calculateCurrentStreak(workoutDays, today)
        assertEquals(1, result)
    }

    @Test
    fun `currentStreak is 0 when last workout was 2 days ago`() {
        val today = LocalDate.of(2026, 3, 3)
        val twoDaysAgo = today.minusDays(2)
        val workoutDays = listOf(twoDaysAgo)
        val result = service.calculateCurrentStreak(workoutDays, today)
        assertEquals(0, result)
    }

    @Test
    fun `currentStreak counts consecutive days ending today`() {
        val today = LocalDate.of(2026, 3, 3)
        val workoutDays = listOf(
            today,
            today.minusDays(1),
            today.minusDays(2),
            today.minusDays(3),
        )
        val result = service.calculateCurrentStreak(workoutDays, today)
        assertEquals(4, result)
    }

    @Test
    fun `currentStreak counts consecutive days ending yesterday`() {
        val today = LocalDate.of(2026, 3, 3)
        val yesterday = today.minusDays(1)
        val workoutDays = listOf(
            yesterday,
            yesterday.minusDays(1),
            yesterday.minusDays(2),
        )
        val result = service.calculateCurrentStreak(workoutDays, today)
        assertEquals(3, result)
    }

    @Test
    fun `currentStreak stops at gap in consecutive days`() {
        val today = LocalDate.of(2026, 3, 3)
        val workoutDays = listOf(
            today,
            today.minusDays(1),
            // gap: minusDays(2) missing
            today.minusDays(3),
            today.minusDays(4),
        )
        val result = service.calculateCurrentStreak(workoutDays, today)
        assertEquals(2, result)
    }

    @Test
    fun `currentStreak handles single day streak with gap before`() {
        val today = LocalDate.of(2026, 3, 3)
        val workoutDays = listOf(
            today,
            today.minusDays(5),
            today.minusDays(6),
        )
        val result = service.calculateCurrentStreak(workoutDays, today)
        assertEquals(1, result)
    }

    @Test
    fun `currentStreak handles multiple workouts on same day`() {
        // Distinct days are passed in -- duplicates should not affect the count
        val today = LocalDate.of(2026, 3, 3)
        val workoutDays = listOf(
            today,
            today.minusDays(1),
        ).distinct().sortedDescending()
        val result = service.calculateCurrentStreak(workoutDays, today)
        assertEquals(2, result)
    }

    // -----------------------------------------------------------------------
    // calculateLongestStreak
    // -----------------------------------------------------------------------

    @Test
    fun `longestStreak is 0 when no workout days`() {
        val result = service.calculateLongestStreak(emptyList())
        assertEquals(0, result)
    }

    @Test
    fun `longestStreak is 1 when only one workout day`() {
        val days = listOf(LocalDate.of(2026, 3, 1))
        val result = service.calculateLongestStreak(days)
        assertEquals(1, result)
    }

    @Test
    fun `longestStreak counts all consecutive days`() {
        val start = LocalDate.of(2026, 2, 24)
        val days = (0L..6L).map { start.plusDays(it) }
        val result = service.calculateLongestStreak(days)
        assertEquals(7, result)
    }

    @Test
    fun `longestStreak finds longest run among multiple runs`() {
        val days = listOf(
            // Run of 2
            LocalDate.of(2026, 1, 1),
            LocalDate.of(2026, 1, 2),
            // Gap
            // Run of 5
            LocalDate.of(2026, 2, 10),
            LocalDate.of(2026, 2, 11),
            LocalDate.of(2026, 2, 12),
            LocalDate.of(2026, 2, 13),
            LocalDate.of(2026, 2, 14),
            // Gap
            // Run of 3
            LocalDate.of(2026, 3, 1),
            LocalDate.of(2026, 3, 2),
            LocalDate.of(2026, 3, 3),
        )
        val result = service.calculateLongestStreak(days)
        assertEquals(5, result)
    }

    @Test
    fun `longestStreak handles non-consecutive days`() {
        val days = listOf(
            LocalDate.of(2026, 1, 1),
            LocalDate.of(2026, 1, 3),
            LocalDate.of(2026, 1, 5),
        )
        val result = service.calculateLongestStreak(days)
        assertEquals(1, result)
    }

    @Test
    fun `longestStreak handles streak spanning month boundary`() {
        val days = listOf(
            LocalDate.of(2026, 1, 30),
            LocalDate.of(2026, 1, 31),
            LocalDate.of(2026, 2, 1),
            LocalDate.of(2026, 2, 2),
        )
        val result = service.calculateLongestStreak(days)
        assertEquals(4, result)
    }

    @Test
    fun `longestStreak handles streak spanning year boundary`() {
        val days = listOf(
            LocalDate.of(2025, 12, 30),
            LocalDate.of(2025, 12, 31),
            LocalDate.of(2026, 1, 1),
            LocalDate.of(2026, 1, 2),
        )
        val result = service.calculateLongestStreak(days)
        assertEquals(4, result)
    }

    // -----------------------------------------------------------------------
    // Combined current + longest streak scenarios
    // -----------------------------------------------------------------------

    @Test
    fun `current streak is subset of longest streak`() {
        val today = LocalDate.of(2026, 3, 3)
        // Longest: 5 days in February; current: 2 days ending today
        val workoutDaysSortedDesc = listOf(
            today,
            today.minusDays(1),
            // gap
            LocalDate.of(2026, 2, 10),
            LocalDate.of(2026, 2, 11),
            LocalDate.of(2026, 2, 12),
            LocalDate.of(2026, 2, 13),
            LocalDate.of(2026, 2, 14),
        ).sortedDescending()

        val current = service.calculateCurrentStreak(workoutDaysSortedDesc, today)
        val longest = service.calculateLongestStreak(workoutDaysSortedDesc.sortedBy { it })

        assertEquals(2, current)
        assertEquals(5, longest)
    }
}
