package com.flomks.sinura.friends

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.pushup.domain.model.FriendActivityStats
import kotlin.math.roundToInt

// ---------------------------------------------------------------------------
// Screen entry point
// ---------------------------------------------------------------------------

/**
 * Friend stats screen.
 *
 * Observes [viewModel] state and delegates all events back to it.
 * [onBack] is called when the user taps the back arrow.
 */
@Composable
fun FriendStatsScreen(
    viewModel: FriendStatsViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()

    FriendStatsContent(
        uiState = uiState,
        onBack = onBack,
        onPeriodSelected = viewModel::onPeriodSelected,
        onRefresh = viewModel::onRefresh,
        modifier = modifier,
    )
}

// ---------------------------------------------------------------------------
// Stateless content (testable / previewable)
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FriendStatsContent(
    uiState: FriendStatsUiState,
    onBack: () -> Unit,
    onPeriodSelected: (StatsPeriod) -> Unit,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            text = uiState.friendName.ifBlank { "Friend" },
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            text = "Activity Stats",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 16.dp),
        ) {
            Spacer(modifier = Modifier.height(8.dp))

            // Period selector chips
            PeriodSelector(
                selectedPeriod = uiState.selectedPeriod,
                onPeriodSelected = onPeriodSelected,
            )

            Spacer(modifier = Modifier.height(16.dp))

            when (val state = uiState.statsState) {
                is FriendStatsState.Loading -> StatsLoadingState()
                is FriendStatsState.Empty   -> StatsEmptyState(
                    friendName = uiState.friendName,
                    period     = uiState.selectedPeriod,
                )
                is FriendStatsState.Error   -> StatsErrorState(message = state.message, onRetry = onRefresh)
                is FriendStatsState.Success -> StatsSuccessContent(stats = state.stats)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Period selector
// ---------------------------------------------------------------------------

@Composable
private fun PeriodSelector(
    selectedPeriod: StatsPeriod,
    onPeriodSelected: (StatsPeriod) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        StatsPeriod.entries.forEach { period ->
            FilterChip(
                selected = period == selectedPeriod,
                onClick = { onPeriodSelected(period) },
                label = { Text(text = period.label) },
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Loading / empty / error states
// ---------------------------------------------------------------------------

@Composable
private fun StatsLoadingState() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator()
    }
}

@Composable
private fun StatsEmptyState(
    friendName: String,
    period: StatsPeriod,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.FitnessCenter,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "No activity yet",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(modifier = Modifier.height(8.dp))
            val periodLabel = when (period) {
                StatsPeriod.DAY   -> "today"
                StatsPeriod.WEEK  -> "this week"
                StatsPeriod.MONTH -> "this month"
            }
            val name = friendName.ifBlank { "Your friend" }
            Text(
                text = "$name hasn't recorded any push-ups $periodLabel.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun StatsErrorState(
    message: String,
    onRetry: () -> Unit,
) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.error.copy(alpha = 0.7f),
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.error,
            )
            Spacer(modifier = Modifier.height(16.dp))
            TextButton(onClick = onRetry) {
                Text(text = "Retry")
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Stats content
// ---------------------------------------------------------------------------

@Composable
private fun StatsSuccessContent(
    stats: FriendActivityStats,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Date range subtitle
        Text(
            text = "${stats.dateFrom}  \u2013  ${stats.dateTo}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(4.dp))

        // Hero push-up card -- full width, visually dominant
        PushUpHeroCard(count = stats.pushupCount)

        // Secondary stats grid (2 columns)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            StatCard(
                label = "Sessions",
                value = stats.totalSessions.toString(),
                modifier = Modifier.weight(1f),
            )
            StatCard(
                label = "Time Earned",
                value = formatSeconds(stats.totalEarnedSeconds),
                modifier = Modifier.weight(1f),
            )
        }

        StatCard(
            label = "Avg Quality",
            value = stats.averageQuality
                ?.let { "${(it * 100).roundToInt()}%" }
                ?: "N/A",
            modifier = Modifier.fillMaxWidth(),
        )

        Spacer(modifier = Modifier.height(8.dp))
    }
}

// ---------------------------------------------------------------------------
// Push-up hero card
// ---------------------------------------------------------------------------

/**
 * Full-width hero card that displays the push-up count as the primary metric.
 *
 * Uses a larger display text style and a distinct primary-tinted background so
 * the number is immediately readable at a glance.
 */
@Composable
private fun PushUpHeroCard(
    count: Int,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 24.dp, horizontal = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = count.toString(),
                style = MaterialTheme.typography.displayLarge,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.FitnessCenter,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
                )
                Text(
                    text = "Push-ups",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Stat card
// ---------------------------------------------------------------------------

@Composable
private fun StatCard(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = value,
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Formats a duration in seconds into a human-readable string.
 *
 * Examples:
 *   0       -> "0 min"
 *   90      -> "1 min"
 *   3600    -> "60 min"
 *   3661    -> "61 min"
 */
private fun formatSeconds(seconds: Long): String {
    val minutes = seconds / 60
    return if (minutes < 60) {
        "$minutes min"
    } else {
        val hours = minutes / 60
        val remainingMinutes = minutes % 60
        if (remainingMinutes == 0L) "${hours}h" else "${hours}h ${remainingMinutes}m"
    }
}

// ---------------------------------------------------------------------------
// Preview
// ---------------------------------------------------------------------------

@Preview
@Composable
private fun FriendStatsScreenPreview() {
    MaterialTheme {
        FriendStatsContent(
            uiState = FriendStatsUiState(
                friendId   = "u1",
                friendName = "Alice Smith",
                selectedPeriod = StatsPeriod.WEEK,
                statsState = FriendStatsState.Success(
                    stats = FriendActivityStats(
                        friendId           = "u1",
                        period             = "week",
                        dateFrom           = "2026-03-02",
                        dateTo             = "2026-03-08",
                        activityPoints     = 142,
                        pushupCount        = 142,
                        totalSessions      = 7,
                        totalEarnedSeconds = 852,
                        averageQuality     = 0.87,
                    ),
                ),
            ),
            onBack = {},
            onPeriodSelected = {},
            onRefresh = {},
        )
    }
}

@Preview
@Composable
private fun FriendStatsLoadingPreview() {
    MaterialTheme {
        FriendStatsContent(
            uiState = FriendStatsUiState(
                friendId   = "u1",
                friendName = "Alice Smith",
                statsState = FriendStatsState.Loading,
            ),
            onBack = {},
            onPeriodSelected = {},
            onRefresh = {},
        )
    }
}

@Preview
@Composable
private fun FriendStatsEmptyPreview() {
    MaterialTheme {
        FriendStatsContent(
            uiState = FriendStatsUiState(
                friendId       = "u1",
                friendName     = "Alice Smith",
                selectedPeriod = StatsPeriod.DAY,
                statsState     = FriendStatsState.Empty,
            ),
            onBack = {},
            onPeriodSelected = {},
            onRefresh = {},
        )
    }
}

@Preview
@Composable
private fun FriendStatsErrorPreview() {
    MaterialTheme {
        FriendStatsContent(
            uiState = FriendStatsUiState(
                friendId   = "u1",
                friendName = "Alice Smith",
                statsState = FriendStatsState.Error("Failed to load stats. Please try again."),
            ),
            onBack = {},
            onPeriodSelected = {},
            onRefresh = {},
        )
    }
}
