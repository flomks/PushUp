package com.flomks.sinura.history

import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Straighten
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sinura.domain.model.JoggingSession
import com.sinura.domain.model.WorkoutSession
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

// ---------------------------------------------------------------------------
// Screen entry point
// ---------------------------------------------------------------------------

/**
 * History screen showing all past workout and jogging sessions.
 *
 * Displays a unified chronological list grouped by day. Each item shows
 * key metrics and can be tapped for details. Jogging sessions show an
 * interactive route map in the detail view.
 */
@Composable
fun HistoryScreen(
    viewModel: HistoryViewModel,
    onJoggingClick: (sessionId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()

    HistoryContent(
        uiState = uiState,
        onRefresh = viewModel::onRefresh,
        onJoggingClick = onJoggingClick,
        modifier = modifier,
    )
}

// ---------------------------------------------------------------------------
// Stateless content
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HistoryContent(
    uiState: HistoryUiState,
    onRefresh: () -> Unit,
    onJoggingClick: (sessionId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "History",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                },
                actions = {
                    IconButton(onClick = onRefresh) {
                        Icon(
                            imageVector = Icons.Default.Refresh,
                            contentDescription = "Refresh",
                        )
                    }
                },
            )
        },
    ) { innerPadding ->
        when (val state = uiState.historyState) {
            is HistoryState.Loading -> HistoryLoadingState(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            )
            is HistoryState.Error -> HistoryErrorState(
                message = state.message,
                onRetry = onRefresh,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            )
            is HistoryState.Success -> {
                if (state.sections.isEmpty()) {
                    HistoryEmptyState(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding),
                    )
                } else {
                    HistoryList(
                        sections = state.sections,
                        onJoggingClick = onJoggingClick,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding),
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Loading / error / empty states
// ---------------------------------------------------------------------------

@Composable
private fun HistoryLoadingState(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier,
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator()
    }
}

@Composable
private fun HistoryErrorState(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier,
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

@Composable
private fun HistoryEmptyState(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier,
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.FitnessCenter,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "No workouts yet",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Complete your first workout to see your history here.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// History list
// ---------------------------------------------------------------------------

@Composable
private fun HistoryList(
    sections: List<HistorySection>,
    onJoggingClick: (sessionId: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        sections.forEach { section ->
            item(key = "header_${section.dateLabel}") {
                SectionHeader(label = section.dateLabel)
            }
            items(
                items = section.items,
                key = { it.id },
            ) { item ->
                when (item) {
                    is HistoryItem.PushUp -> PushUpHistoryCard(session = item.session)
                    is HistoryItem.Jogging -> JoggingHistoryCard(
                        session = item.session,
                        onClick = { onJoggingClick(item.session.id) },
                    )
                }
            }
            item(key = "spacer_${section.dateLabel}") {
                Spacer(modifier = Modifier.height(8.dp))
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

@Composable
private fun SectionHeader(
    label: String,
    modifier: Modifier = Modifier,
) {
    Text(
        text = label,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.padding(vertical = 8.dp),
    )
}

// ---------------------------------------------------------------------------
// Push-up history card
// ---------------------------------------------------------------------------

@Composable
private fun PushUpHistoryCard(
    session: WorkoutSession,
    modifier: Modifier = Modifier,
) {
    val tz = TimeZone.currentSystemDefault()
    val localTime = session.startedAt.toLocalDateTime(tz)
    val timeStr = "${localTime.hour.toString().padStart(2, '0')}:${localTime.minute.toString().padStart(2, '0')}"

    val durationSeconds = session.endedAt?.let {
        (it.epochSeconds - session.startedAt.epochSeconds).toInt()
    } ?: 0
    val durationStr = formatDuration(durationSeconds)
    val earnedMin = session.earnedTimeCreditSeconds / 60

    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Activity type icon
            Icon(
                imageVector = Icons.Default.FitnessCenter,
                contentDescription = "Push-ups",
                modifier = Modifier.size(32.dp),
                tint = MaterialTheme.colorScheme.primary,
            )

            Spacer(modifier = Modifier.width(12.dp))

            // Main content
            Column(modifier = Modifier.weight(1f)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "Push-ups",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = timeStr,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                Spacer(modifier = Modifier.height(4.dp))

                Row(
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    MetricChip(
                        icon = Icons.Default.FitnessCenter,
                        text = "${session.pushUpCount} reps",
                    )
                    MetricChip(
                        icon = Icons.Default.Timer,
                        text = durationStr,
                    )
                    MetricChip(
                        icon = Icons.Default.Schedule,
                        text = "+${earnedMin} min",
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Jogging history card
// ---------------------------------------------------------------------------

@Composable
private fun JoggingHistoryCard(
    session: JoggingSession,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tz = TimeZone.currentSystemDefault()
    val localTime = session.startedAt.toLocalDateTime(tz)
    val timeStr = "${localTime.hour.toString().padStart(2, '0')}:${localTime.minute.toString().padStart(2, '0')}"

    val durationStr = formatDuration(session.durationSeconds.toInt())
    val distanceStr = formatDistance(session.distanceMeters)
    val earnedMin = session.earnedTimeCreditSeconds / 60

    Card(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.secondaryContainer,
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Activity type icon
            Icon(
                imageVector = Icons.AutoMirrored.Filled.DirectionsRun,
                contentDescription = "Running",
                modifier = Modifier.size(32.dp),
                tint = MaterialTheme.colorScheme.secondary,
            )

            Spacer(modifier = Modifier.width(12.dp))

            // Main content
            Column(modifier = Modifier.weight(1f)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "Running",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = timeStr,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                }

                Spacer(modifier = Modifier.height(4.dp))

                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    MetricChip(
                        icon = Icons.Default.Straighten,
                        text = distanceStr,
                    )
                    MetricChip(
                        icon = Icons.Default.Timer,
                        text = durationStr,
                    )
                    MetricChip(
                        icon = Icons.Default.Speed,
                        text = session.formattedPace + "/km",
                    )
                    MetricChip(
                        icon = Icons.Default.Schedule,
                        text = "+${earnedMin} min",
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Metric chip
// ---------------------------------------------------------------------------

@Composable
private fun MetricChip(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(14.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
        )
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

private fun formatDuration(totalSeconds: Int): String {
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "${minutes}:${seconds.toString().padStart(2, '0')}"
}

private fun formatDistance(meters: Double): String {
    return if (meters >= 1000) {
        val km = meters / 1000.0
        "${formatDecimal(km, 2)} km"
    } else {
        "${meters.toInt()} m"
    }
}
