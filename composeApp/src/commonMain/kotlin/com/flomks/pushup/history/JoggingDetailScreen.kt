package com.flomks.pushup.history

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
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.LocalFireDepartment
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pushup.domain.model.JoggingSession
import com.pushup.domain.model.RoutePoint
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

// ---------------------------------------------------------------------------
// Screen entry point
// ---------------------------------------------------------------------------

/**
 * Detail screen for a completed jogging session.
 *
 * Shows key running metrics (distance, duration, pace, calories, earned time)
 * and an interactive route map with timestamp tooltips.
 */
@Composable
fun JoggingDetailScreen(
    viewModel: HistoryViewModel,
    sessionId: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LaunchedEffect(sessionId) {
        viewModel.loadJoggingDetail(sessionId)
    }

    val detailUiState by viewModel.detailState.collectAsState()

    JoggingDetailContent(
        uiState = detailUiState,
        onBack = onBack,
        onRetry = { viewModel.loadJoggingDetail(sessionId) },
        modifier = modifier,
    )
}

// ---------------------------------------------------------------------------
// Stateless content
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun JoggingDetailContent(
    uiState: JoggingDetailUiState,
    onBack: () -> Unit,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "Running Details",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
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
        when (val state = uiState.detailState) {
            is JoggingDetailState.Loading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            is JoggingDetailState.Error -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
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
                            text = state.message,
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
            is JoggingDetailState.Success -> {
                JoggingDetailSuccessContent(
                    session = state.session,
                    routePoints = state.routePoints,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Success content
// ---------------------------------------------------------------------------

@Composable
private fun JoggingDetailSuccessContent(
    session: JoggingSession,
    routePoints: List<RoutePoint>,
    modifier: Modifier = Modifier,
) {
    val tz = TimeZone.currentSystemDefault()
    val localDateTime = session.startedAt.toLocalDateTime(tz)
    val dateStr = "${localDateTime.dayOfMonth}. ${localDateTime.month.name.lowercase().replaceFirstChar { it.uppercase() }} ${localDateTime.year}"
    val timeStr = "${localDateTime.hour.toString().padStart(2, '0')}:${localDateTime.minute.toString().padStart(2, '0')}"

    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Date and time header
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.secondaryContainer,
            ),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(20.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.DirectionsRun,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp),
                    tint = MaterialTheme.colorScheme.onSecondaryContainer,
                )
                Column {
                    Text(
                        text = "Running",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                    Text(
                        text = "$dateStr at $timeStr",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.7f),
                    )
                }
            }
        }

        // Stats grid
        StatsGrid(session = session)

        // Route map
        Text(
            text = "Route",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )

        Text(
            text = if (routePoints.isNotEmpty()) {
                "Tap on the route to see timestamps and speed at each point."
            } else {
                "No GPS route data was recorded for this session."
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
        )

        RouteMapView(
            routePoints = routePoints,
            modifier = Modifier
                .fillMaxWidth()
                .height(350.dp),
        )

        // Route stats summary
        if (routePoints.isNotEmpty()) {
            RouteStatsSummary(routePoints = routePoints)
        }

        Spacer(modifier = Modifier.height(8.dp))
    }
}

// ---------------------------------------------------------------------------
// Stats grid
// ---------------------------------------------------------------------------

@Composable
private fun StatsGrid(
    session: JoggingSession,
    modifier: Modifier = Modifier,
) {
    val distanceStr = if (session.distanceMeters >= 1000) {
        "${formatDecimal(session.distanceKm, 2)} km"
    } else {
        "${session.distanceMeters.toInt()} m"
    }

    val durationMin = session.durationSeconds / 60
    val durationSec = session.durationSeconds % 60
    val durationStr = "${durationMin}:${durationSec.toString().padStart(2, '0')}"

    val earnedMin = session.earnedTimeCreditSeconds / 60

    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Distance hero card
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer,
            ),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Straighten,
                    contentDescription = null,
                    modifier = Modifier.size(32.dp),
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                )
                Column {
                    Text(
                        text = distanceStr,
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                    Text(
                        text = "Distance",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
                    )
                }
            }
        }

        // 2-column grid
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            StatCard(
                icon = Icons.Default.Timer,
                value = durationStr,
                label = "Duration",
                modifier = Modifier.weight(1f),
            )
            StatCard(
                icon = Icons.Default.Speed,
                value = session.formattedPace + "/km",
                label = "Avg Pace",
                modifier = Modifier.weight(1f),
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            StatCard(
                icon = Icons.Default.LocalFireDepartment,
                value = "${session.caloriesBurned} kcal",
                label = "Calories",
                modifier = Modifier.weight(1f),
            )
            StatCard(
                icon = Icons.Default.Schedule,
                value = "+${earnedMin} min",
                label = "Screen Time Earned",
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun StatCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    value: String,
    label: String,
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
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = value,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Route stats summary
// ---------------------------------------------------------------------------

@Composable
private fun RouteStatsSummary(
    routePoints: List<RoutePoint>,
    modifier: Modifier = Modifier,
) {
    val pointCount = routePoints.size
    val maxSpeed = routePoints.mapNotNull { it.speed }.maxOrNull()
    val avgSpeed = routePoints.mapNotNull { it.speed }.let { speeds ->
        if (speeds.isNotEmpty()) speeds.average() else null
    }
    val elevationGain = computeElevationGain(routePoints)

    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "Route Details",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )

            RouteDetailRow(label = "GPS Points", value = "$pointCount")

            maxSpeed?.let {
                RouteDetailRow(
                    label = "Max Speed",
                    value = "${formatDecimal(it * 3.6, 1)} km/h",
                )
            }

            avgSpeed?.let {
                RouteDetailRow(
                    label = "Avg Speed",
                    value = "${formatDecimal(it * 3.6, 1)} km/h",
                )
            }

            if (elevationGain > 0) {
                RouteDetailRow(
                    label = "Elevation Gain",
                    value = "${formatDecimal(elevationGain, 0)} m",
                )
            }
        }
    }
}

@Composable
private fun RouteDetailRow(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun computeElevationGain(points: List<RoutePoint>): Double {
    var gain = 0.0
    for (i in 1 until points.size) {
        val prev = points[i - 1].altitude ?: continue
        val curr = points[i].altitude ?: continue
        val diff = curr - prev
        if (diff > 0) gain += diff
    }
    return gain
}
