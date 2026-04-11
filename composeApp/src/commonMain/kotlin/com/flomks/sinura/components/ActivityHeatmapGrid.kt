package com.flomks.sinura.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sinura.domain.model.ActivityDayStats
import com.sinura.domain.model.HeatmapCalculator
import com.sinura.domain.model.HeatmapIntensity
import com.sinura.domain.model.MonthlyActivitySummary
import kotlinx.datetime.DayOfWeek
import kotlinx.datetime.LocalDate
import kotlinx.datetime.Month

/**
 * GitHub-style activity heatmap grid displaying a monthly calendar
 * with colour-coded intensity levels based on daily workout activity.
 *
 * Each day cell is shaded from transparent (no activity) to full green
 * (maximum activity), using 5 intensity levels computed relative to the
 * user's own 90th-percentile active day.
 */
@Composable
fun ActivityHeatmapGrid(
    summary: MonthlyActivitySummary,
    onPreviousMonth: () -> Unit,
    onNextMonth: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val referenceMax = HeatmapCalculator.calculateReferenceMax(summary.days)
    val monthName = Month(summary.month).name.lowercase()
        .replaceFirstChar { it.uppercase() }

    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
        ) {
            // Month navigation header
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                IconButton(onClick = onPreviousMonth) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                        contentDescription = "Previous month",
                    )
                }
                Text(
                    text = "$monthName ${summary.year}",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                IconButton(onClick = onNextMonth) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = "Next month",
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Day-of-week headers (Mo - Su)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                listOf("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su").forEach { label ->
                    Text(
                        text = label,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            Spacer(modifier = Modifier.height(4.dp))

            // Build grid cells: leading empty cells + day cells
            val firstDay = LocalDate(summary.year, summary.month, 1)
            val leadingEmpty = mondayBasedOffset(firstDay.dayOfWeek)

            // Rows of 7 cells
            val cells = buildList {
                repeat(leadingEmpty) { add(null) }
                addAll(summary.days)
            }

            // Render rows
            val rows = cells.chunked(7)
            Column(
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                rows.forEach { row ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(3.dp),
                    ) {
                        row.forEach { dayStats ->
                            DayCell(
                                dayStats = dayStats,
                                referenceMax = referenceMax,
                                modifier = Modifier.weight(1f),
                            )
                        }
                        // Pad trailing cells in last row
                        repeat(7 - row.size) {
                            Box(modifier = Modifier.weight(1f))
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Summary stats below grid
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                SummaryItem(
                    label = "Active Days",
                    value = "${summary.activeDays} / ${summary.days.size}",
                )
                SummaryItem(
                    label = "Daily Average",
                    value = formatSeconds(summary.averageEarnedSecondsPerActiveDay),
                )
                SummaryItem(
                    label = "Total",
                    value = formatSeconds(summary.totalEarnedSeconds),
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Day cell
// ---------------------------------------------------------------------------

@Composable
private fun DayCell(
    dayStats: ActivityDayStats?,
    referenceMax: Long,
    modifier: Modifier = Modifier,
) {
    if (dayStats == null) {
        // Empty leading cell
        Box(
            modifier = modifier
                .aspectRatio(1f)
                .clip(RoundedCornerShape(6.dp)),
        )
        return
    }

    val intensity = HeatmapCalculator.calculateIntensity(
        earnedSeconds = dayStats.totalEarnedSeconds,
        referenceMax = referenceMax,
    )
    val bgColor = intensityColor(intensity)
    val textColor = if (intensity == HeatmapIntensity.MAX) {
        Color.Black
    } else {
        MaterialTheme.colorScheme.onSurface.copy(
            alpha = if (intensity == HeatmapIntensity.NONE) 0.25f else 0.85f,
        )
    }

    Box(
        modifier = modifier
            .aspectRatio(1f)
            .clip(RoundedCornerShape(6.dp))
            .background(bgColor),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = dayStats.date.dayOfMonth.toString(),
            fontSize = 11.sp,
            fontWeight = if (intensity >= HeatmapIntensity.HIGH) FontWeight.Medium else FontWeight.Normal,
            color = textColor,
        )
    }
}

// ---------------------------------------------------------------------------
// Summary item
// ---------------------------------------------------------------------------

@Composable
private fun SummaryItem(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
        )
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Maps [HeatmapIntensity] to a green-based colour (GitHub-style).
 */
@Composable
private fun intensityColor(intensity: HeatmapIntensity): Color {
    val surfaceVariant = MaterialTheme.colorScheme.surfaceVariant
    return when (intensity) {
        HeatmapIntensity.NONE   -> surfaceVariant.copy(alpha = 0.3f)
        HeatmapIntensity.LOW    -> Color(0xFF0E4429)
        HeatmapIntensity.MEDIUM -> Color(0xFF006D32)
        HeatmapIntensity.HIGH   -> Color(0xFF26A641)
        HeatmapIntensity.MAX    -> Color(0xFF39D353)
    }
}

/**
 * Returns the 0-based offset from Monday for a given [DayOfWeek].
 * Monday = 0, Sunday = 6.
 */
private fun mondayBasedOffset(dayOfWeek: DayOfWeek): Int = when (dayOfWeek) {
    DayOfWeek.MONDAY    -> 0
    DayOfWeek.TUESDAY   -> 1
    DayOfWeek.WEDNESDAY -> 2
    DayOfWeek.THURSDAY  -> 3
    DayOfWeek.FRIDAY    -> 4
    DayOfWeek.SATURDAY  -> 5
    DayOfWeek.SUNDAY    -> 6
    else -> 0
}

/**
 * Formats seconds into a human-readable duration (e.g. "1h 23m" or "45m").
 */
private fun formatSeconds(seconds: Long): String {
    if (seconds <= 0) return "0m"
    val hours = seconds / 3600
    val minutes = (seconds % 3600) / 60
    return when {
        hours > 0 && minutes > 0 -> "${hours}h ${minutes}m"
        hours > 0 -> "${hours}h"
        else -> "${minutes}m"
    }
}
