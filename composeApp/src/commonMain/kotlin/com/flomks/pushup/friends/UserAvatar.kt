package com.flomks.pushup.friends

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

// ---------------------------------------------------------------------------
// Shared avatar composable
// ---------------------------------------------------------------------------

/**
 * Circular avatar showing the user's initials.
 *
 * Extracts the first letter of up to two words (split on space or underscore)
 * and renders them inside a [CircleShape] with the theme's primary container
 * colour.
 *
 * When a real image loading library (Coil/Kamel) is available, this composable
 * should be extended to accept an optional `avatarUrl` parameter and load the
 * image asynchronously, falling back to initials on error.
 *
 * @param displayName The name to derive initials from.
 * @param modifier    Optional [Modifier] for the outer container.
 */
@Composable
fun UserAvatar(
    displayName: String,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .size(48.dp)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.primaryContainer),
        contentAlignment = Alignment.Center,
    ) {
        val initials = displayName
            .split(" ", "_")
            .take(2)
            .mapNotNull { it.firstOrNull()?.uppercaseChar() }
            .joinToString("")
            .ifEmpty { "?" }

        Text(
            text = initials,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onPrimaryContainer,
            fontWeight = FontWeight.Bold,
        )
    }
}
