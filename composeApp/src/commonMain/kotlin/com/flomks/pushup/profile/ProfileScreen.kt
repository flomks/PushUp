package com.flomks.pushup.profile

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
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
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.flomks.pushup.components.ActivityHeatmapGrid
import com.pushup.domain.model.ActivityDayStats
import com.pushup.domain.model.LevelCalculator
import com.pushup.domain.model.MonthlyActivitySummary
import com.pushup.domain.model.TotalStats
import com.pushup.domain.model.User
import com.pushup.domain.model.UserLevel
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate

// ---------------------------------------------------------------------------
// Screen entry point
// ---------------------------------------------------------------------------

/**
 * Profile screen.
 *
 * Observes [viewModel] state and delegates all events back to it.
 */
@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()

    ProfileContent(
        uiState = uiState,
        onRefresh = viewModel::onRefresh,
        onPreviousMonth = viewModel::onPreviousMonth,
        onNextMonth = viewModel::onNextMonth,
        modifier = modifier,
    )
}

// ---------------------------------------------------------------------------
// Stateless content (testable / previewable)
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ProfileContent(
    uiState: ProfileUiState,
    onRefresh: () -> Unit,
    onPreviousMonth: () -> Unit,
    onNextMonth: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "Profile",
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
        when (val state = uiState.profileState) {
            is ProfileState.Loading -> ProfileLoadingState(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            )
            is ProfileState.Error   -> ProfileErrorState(
                message = state.message,
                onRetry = onRefresh,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            )
            is ProfileState.Success -> ProfileSuccessContent(
                state = state,
                onPreviousMonth = onPreviousMonth,
                onNextMonth = onNextMonth,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Loading / error states
// ---------------------------------------------------------------------------

@Composable
private fun ProfileLoadingState(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier,
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator()
    }
}

@Composable
private fun ProfileErrorState(
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

// ---------------------------------------------------------------------------
// Success content
// ---------------------------------------------------------------------------

@Composable
private fun ProfileSuccessContent(
    state: ProfileState.Success,
    onPreviousMonth: () -> Unit,
    onNextMonth: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // User avatar + display name
        UserHeader(user = state.user)

        // Level card (hero element)
        LevelCard(userLevel = state.userLevel)

        // Activity heatmap (GitHub-style)
        state.monthlyActivity?.let { summary ->
            ActivityHeatmapGrid(
                summary = summary,
                onPreviousMonth = onPreviousMonth,
                onNextMonth = onNextMonth,
            )
        }

        // Stats grid — now activity-focused
        StatsSection(
            totalStats = state.totalStats,
            activityStreakCurrent = state.activityStreakCurrent,
            activityStreakLongest = state.activityStreakLongest,
        )

        Spacer(modifier = Modifier.height(8.dp))
    }
}

// ---------------------------------------------------------------------------
// User header
// ---------------------------------------------------------------------------

@Composable
private fun UserHeader(
    user: User,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Avatar placeholder
        Surface(
            modifier = Modifier
                .size(64.dp)
                .clip(CircleShape),
            color = MaterialTheme.colorScheme.primaryContainer,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = Icons.Default.Person,
                    contentDescription = null,
                    modifier = Modifier.size(36.dp),
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }
        }

        Column {
            Text(
                text = user.displayName,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = user.email,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Level card
// ---------------------------------------------------------------------------

/**
 * Hero card displaying the user's current level, XP progress bar, and XP totals.
 */
@Composable
private fun LevelCard(
    userLevel: UserLevel,
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
                .padding(20.dp),
        ) {
            // Level badge row
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column {
                    Text(
                        text = "Level",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
                    )
                    Text(
                        text = userLevel.level.toString(),
                        style = MaterialTheme.typography.displayMedium,
                        fontWeight = FontWeight.ExtraBold,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }

                // Star icon as level badge
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(56.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Default.Star,
                            contentDescription = null,
                            modifier = Modifier.size(32.dp),
                            tint = MaterialTheme.colorScheme.onPrimary,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // XP progress bar
            Text(
                text = "XP Progress",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
            )
            Spacer(modifier = Modifier.height(6.dp))
            LinearProgressIndicator(
                progress = { userLevel.levelProgress },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(10.dp)
                    .clip(RoundedCornerShape(5.dp)),
                color = MaterialTheme.colorScheme.primary,
                trackColor = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.15f),
            )
            Spacer(modifier = Modifier.height(6.dp))

            // XP numbers
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = "${userLevel.xpIntoLevel} XP",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f),
                )
                Text(
                    text = "${userLevel.xpRequiredForNextLevel} XP to next level",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f),
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Total XP
            Text(
                text = "Total XP: ${userLevel.totalXp}",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Stats section — now activity-focused
// ---------------------------------------------------------------------------

@Composable
private fun StatsSection(
    totalStats: TotalStats?,
    activityStreakCurrent: Int,
    activityStreakLongest: Int,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = "Lifetime Stats",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )

        // Total Workouts hero card
        Card(
            modifier = Modifier.fillMaxWidth(),
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
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.FitnessCenter,
                    contentDescription = null,
                    modifier = Modifier.size(32.dp),
                    tint = MaterialTheme.colorScheme.onSecondaryContainer,
                )
                Column {
                    Text(
                        text = (totalStats?.totalSessions ?: 0).toString(),
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                    Text(
                        text = "Total Workouts",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.7f),
                    )
                }
            }
        }

        // 2-column grid for secondary stats
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SmallStatCard(
                label = "Time Earned",
                value = formatEarnedTime(totalStats?.totalEarnedSeconds ?: 0),
                modifier = Modifier.weight(1f),
            )
            SmallStatCard(
                label = "Push-ups",
                value = (totalStats?.totalPushUps ?: 0).toString(),
                modifier = Modifier.weight(1f),
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SmallStatCard(
                label = "Current Streak",
                value = "$activityStreakCurrent days",
                modifier = Modifier.weight(1f),
            )
            SmallStatCard(
                label = "Longest Streak",
                value = "$activityStreakLongest days",
                modifier = Modifier.weight(1f),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Small stat card
// ---------------------------------------------------------------------------

@Composable
private fun SmallStatCard(
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
                style = MaterialTheme.typography.headlineSmall,
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

private fun formatEarnedTime(seconds: Long): String {
    if (seconds <= 0) return "0m"
    val hours = seconds / 3600
    val minutes = (seconds % 3600) / 60
    return when {
        hours > 0 && minutes > 0 -> "${hours}h ${minutes}m"
        hours > 0 -> "${hours}h"
        else -> "${minutes}m"
    }
}

// ---------------------------------------------------------------------------
// Previews
// ---------------------------------------------------------------------------

@Preview
@Composable
private fun ProfileSuccessPreview() {
    val createdAt = Instant.fromEpochMilliseconds(1_700_000_000_000L)
    MaterialTheme {
        ProfileContent(
            uiState = ProfileUiState(
                profileState = ProfileState.Success(
                    user = User(
                        id = "u1",
                        email = "max@example.com",
                        displayName = "Max Mustermann",
                        createdAt = createdAt,
                        lastSyncedAt = createdAt,
                    ),
                    userLevel = LevelCalculator.fromTotalXp("u1", 1250L),
                    totalStats = TotalStats(
                        userId = "u1",
                        totalPushUps = 842,
                        totalSessions = 34,
                        totalEarnedSeconds = 5040,
                        totalSpentSeconds = 1800,
                        averageQuality = 0.76f,
                        averagePushUpsPerSession = 24.8f,
                        bestSession = 60,
                        currentStreakDays = 5,
                        longestStreakDays = 12,
                    ),
                    monthlyActivity = MonthlyActivitySummary(
                        month = 4,
                        year = 2026,
                        days = (1..30).map { day ->
                            ActivityDayStats(
                                date = LocalDate(2026, 4, day),
                                totalSessions = if (day % 3 != 0) 1 else 0,
                                totalEarnedSeconds = if (day % 3 != 0) (day * 60L) else 0L,
                                workoutTypes = emptySet(),
                            )
                        },
                    ),
                    activityStreakCurrent = 7,
                    activityStreakLongest = 14,
                ),
            ),
            onRefresh = {},
            onPreviousMonth = {},
            onNextMonth = {},
        )
    }
}

@Preview
@Composable
private fun ProfileLoadingPreview() {
    MaterialTheme {
        ProfileContent(
            uiState = ProfileUiState(profileState = ProfileState.Loading),
            onRefresh = {},
            onPreviousMonth = {},
            onNextMonth = {},
        )
    }
}

@Preview
@Composable
private fun ProfileErrorPreview() {
    MaterialTheme {
        ProfileContent(
            uiState = ProfileUiState(
                profileState = ProfileState.Error("No authenticated user found. Please sign in."),
            ),
            onRefresh = {},
            onPreviousMonth = {},
            onNextMonth = {},
        )
    }
}
