package com.flomks.sinura.history

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.FitScreen
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sinura.domain.model.JoggingSegment
import com.sinura.domain.model.JoggingSegmentType
import com.sinura.domain.model.RoutePoint
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import kotlin.math.sqrt

// ---------------------------------------------------------------------------
// Route map composable
// ---------------------------------------------------------------------------

/**
 * Interactive route map that displays GPS route points on a canvas.
 *
 * Supports:
 * - Pan (drag) and zoom (pinch / buttons)
 * - Route line with separate coloring for running and paused segments
 * - Start/end markers
 * - Timestamp tooltips when tapping near a route point
 * - Zoom controls and fit-to-route button
 *
 * This is a pure Compose implementation that works on all KMP targets
 * (Android, Desktop) without requiring platform-specific WebView or map SDKs.
 */
@Composable
fun RouteMapView(
    routePoints: List<RoutePoint>,
    segments: List<JoggingSegment> = emptyList(),
    modifier: Modifier = Modifier,
) {
    if (routePoints.isEmpty()) {
        EmptyRouteView(modifier = modifier)
        return
    }

    // Compute bounding box
    val bounds = remember(routePoints) { computeBounds(routePoints) }
    val routeSegments = remember(routePoints, segments) {
        buildDisplaySegments(routePoints, segments)
    }

    // Transform state
    var scale by remember { mutableFloatStateOf(1f) }
    var offsetX by remember { mutableFloatStateOf(0f) }
    var offsetY by remember { mutableFloatStateOf(0f) }

    // Selected point for tooltip
    var selectedPoint by remember { mutableStateOf<RoutePoint?>(null) }

    val textMeasurer = rememberTextMeasurer()

    // Colors
    val routeColor = MaterialTheme.colorScheme.primary
    val pauseColor = MaterialTheme.colorScheme.tertiary
    val startColor = Color(0xFF4CAF50) // green
    val endColor = Color(0xFFF44336) // red
    val backgroundColor = MaterialTheme.colorScheme.surfaceVariant
    val gridColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.1f)
    val tooltipBg = MaterialTheme.colorScheme.inverseSurface
    val tooltipText = MaterialTheme.colorScheme.inverseOnSurface

    Box(modifier = modifier) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .clip(RoundedCornerShape(12.dp))
                .background(backgroundColor)
                .pointerInput(Unit) {
                    detectTransformGestures { _, pan, zoom, _ ->
                        scale = (scale * zoom).coerceIn(0.5f, 10f)
                        offsetX += pan.x
                        offsetY += pan.y
                    }
                }
                .pointerInput(routePoints) {
                    detectTapGestures { tapOffset ->
                        // Find nearest route point to tap
                        val nearest = findNearestPoint(
                            tapOffset = tapOffset,
                            routePoints = routePoints,
                            bounds = bounds,
                            canvasSize = Size(size.width.toFloat(), size.height.toFloat()),
                            scale = scale,
                            panOffsetX = offsetX,
                            panOffsetY = offsetY,
                        )
                        selectedPoint = if (nearest == selectedPoint) null else nearest
                    }
                },
        ) {
            val canvasWidth = size.width
            val canvasHeight = size.height
            val padding = 40f

            // Draw grid
            drawGrid(gridColor, padding)

            // Map coordinates to canvas
            val effectiveWidth = (canvasWidth - 2 * padding) * scale
            val effectiveHeight = (canvasHeight - 2 * padding) * scale

            val latRange = bounds.maxLat - bounds.minLat
            val lonRange = bounds.maxLon - bounds.minLon

            // Maintain aspect ratio using Mercator-like projection
            val latMid = (bounds.minLat + bounds.maxLat) / 2.0
            val cosLat = cos(latMid * PI / 180.0)
            val adjustedLonRange = lonRange * cosLat

            val dataAspect = if (latRange > 0 && adjustedLonRange > 0) {
                adjustedLonRange / latRange
            } else {
                1.0
            }
            val canvasAspect = effectiveWidth / effectiveHeight

            val scaleX: Float
            val scaleY: Float
            val drawOffsetX: Float
            val drawOffsetY: Float

            if (dataAspect > canvasAspect) {
                // Width-constrained
                scaleX = effectiveWidth.toFloat()
                scaleY = (effectiveWidth / dataAspect).toFloat()
                drawOffsetX = padding + offsetX
                drawOffsetY = padding + (effectiveHeight - scaleY) / 2f + offsetY
            } else {
                // Height-constrained
                scaleY = effectiveHeight.toFloat()
                scaleX = (effectiveHeight * dataAspect).toFloat()
                drawOffsetX = padding + (effectiveWidth - scaleX) / 2f + offsetX
                drawOffsetY = padding + offsetY
            }

            fun mapPoint(point: RoutePoint): Offset {
                val x = if (lonRange > 0) {
                    ((point.longitude - bounds.minLon) * cosLat / (lonRange * cosLat) * scaleX).toFloat()
                } else {
                    scaleX / 2f
                }
                // Invert Y because canvas Y goes down but latitude goes up
                val y = if (latRange > 0) {
                    ((1.0 - (point.latitude - bounds.minLat) / latRange) * scaleY).toFloat()
                } else {
                    scaleY / 2f
                }
                return Offset(drawOffsetX + x, drawOffsetY + y)
            }

            // Draw route line, coloring paused movement separately from active running.
            if (routeSegments.isNotEmpty()) {
                for (segment in routeSegments) {
                    val from = mapPoint(segment.from)
                    val to = mapPoint(segment.to)

                    drawLine(
                        color = if (segment.type == JoggingSegmentType.PAUSE) {
                            pauseColor
                        } else {
                            routeColor
                        },
                        start = from,
                        end = to,
                        strokeWidth = 4f * scale.coerceIn(0.5f, 3f),
                        cap = StrokeCap.Round,
                    )
                }

                // Draw route outline for better visibility
                val outlinePath = Path().apply {
                    val first = mapPoint(routePoints.first())
                    moveTo(first.x, first.y)
                    for (i in 1 until routePoints.size) {
                        val p = mapPoint(routePoints[i])
                        lineTo(p.x, p.y)
                    }
                }
                drawPath(
                    path = outlinePath,
                    color = routeColor.copy(alpha = 0.2f),
                    style = Stroke(
                        width = 10f * scale.coerceIn(0.5f, 3f),
                        cap = StrokeCap.Round,
                        join = StrokeJoin.Round,
                    ),
                )
            }

            // Draw timestamp markers at intervals
            val markerInterval = max(1, routePoints.size / 8)
            for (i in routePoints.indices step markerInterval) {
                if (i == 0 || i == routePoints.size - 1) continue
                val point = routePoints[i]
                val pos = mapPoint(point)
                drawCircle(
                    color = routeColor.copy(alpha = 0.6f),
                    radius = 4f * scale.coerceIn(0.5f, 2f),
                    center = pos,
                )
            }

            // Draw start marker (green)
            val startPos = mapPoint(routePoints.first())
            drawCircle(color = startColor, radius = 10f, center = startPos)
            drawCircle(color = Color.White, radius = 6f, center = startPos)
            drawCircle(color = startColor, radius = 4f, center = startPos)

            // Draw end marker (red)
            val endPos = mapPoint(routePoints.last())
            drawCircle(color = endColor, radius = 10f, center = endPos)
            drawCircle(color = Color.White, radius = 6f, center = endPos)
            drawCircle(color = endColor, radius = 4f, center = endPos)

            // Draw tooltip for selected point
            selectedPoint?.let { point ->
                val pos = mapPoint(point)
                val tz = TimeZone.currentSystemDefault()
                val localTime = point.timestamp.toLocalDateTime(tz)
                val timeStr = "${localTime.hour.toString().padStart(2, '0')}:${localTime.minute.toString().padStart(2, '0')}:${localTime.second.toString().padStart(2, '0')}"

                val speedStr = point.speed?.let { "${formatDecimal(it * 3.6, 1)} km/h" } ?: ""
                val distStr = "${point.distanceFromStart.roundToInt()} m"
                val label = "$timeStr | $distStr${if (speedStr.isNotEmpty()) " | $speedStr" else ""}"

                // Highlight selected point
                drawCircle(color = routeColor, radius = 8f, center = pos)
                drawCircle(color = Color.White, radius = 5f, center = pos)

                // Draw tooltip
                val textLayout = textMeasurer.measure(
                    text = label,
                    style = TextStyle(
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                )
                val tooltipWidth = textLayout.size.width + 16f
                val tooltipHeight = textLayout.size.height + 12f

                // Position tooltip above the point
                val tooltipX = (pos.x - tooltipWidth / 2f)
                    .coerceIn(4f, canvasWidth - tooltipWidth - 4f)
                val tooltipY = pos.y - tooltipHeight - 16f

                // Background
                drawRoundRect(
                    color = tooltipBg,
                    topLeft = Offset(tooltipX, tooltipY),
                    size = Size(tooltipWidth, tooltipHeight),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(6f, 6f),
                )

                // Text
                drawText(
                    textLayoutResult = textLayout,
                    color = tooltipText,
                    topLeft = Offset(tooltipX + 8f, tooltipY + 6f),
                )

                // Arrow pointing down to the point
                val arrowPath = Path().apply {
                    moveTo(pos.x - 6f, tooltipY + tooltipHeight)
                    lineTo(pos.x, tooltipY + tooltipHeight + 6f)
                    lineTo(pos.x + 6f, tooltipY + tooltipHeight)
                    close()
                }
                drawPath(path = arrowPath, color = tooltipBg)
            }
        }

        // Zoom controls overlay
        Column(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(8.dp),
        ) {
            FilledIconButton(
                onClick = { scale = (scale * 1.3f).coerceAtMost(10f) },
                modifier = Modifier.size(36.dp),
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f),
                ),
            ) {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = "Zoom in",
                    modifier = Modifier.size(18.dp),
                )
            }
            Spacer(modifier = Modifier.height(4.dp))
            FilledIconButton(
                onClick = { scale = (scale / 1.3f).coerceAtLeast(0.5f) },
                modifier = Modifier.size(36.dp),
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f),
                ),
            ) {
                Icon(
                    imageVector = Icons.Default.Remove,
                    contentDescription = "Zoom out",
                    modifier = Modifier.size(18.dp),
                )
            }
            Spacer(modifier = Modifier.height(4.dp))
            FilledIconButton(
                onClick = {
                    scale = 1f
                    offsetX = 0f
                    offsetY = 0f
                    selectedPoint = null
                },
                modifier = Modifier.size(36.dp),
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f),
                ),
            ) {
                Icon(
                    imageVector = Icons.Default.FitScreen,
                    contentDescription = "Fit to route",
                    modifier = Modifier.size(18.dp),
                )
            }
        }

        // Legend
        Row(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(8.dp)
                .background(
                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f),
                    shape = RoundedCornerShape(8.dp),
                )
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(
                modifier = Modifier.size(8.dp),
                shape = CircleShape,
                color = startColor,
            ) {}
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = "Start",
                style = MaterialTheme.typography.labelSmall,
            )
            Spacer(modifier = Modifier.width(12.dp))
            Surface(
                modifier = Modifier.size(8.dp),
                shape = CircleShape,
                color = routeColor,
            ) {}
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = "Run",
                style = MaterialTheme.typography.labelSmall,
            )
            Spacer(modifier = Modifier.width(12.dp))
            Surface(
                modifier = Modifier.size(8.dp),
                shape = CircleShape,
                color = pauseColor,
            ) {}
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = "Pause",
                style = MaterialTheme.typography.labelSmall,
            )
            Spacer(modifier = Modifier.width(12.dp))
            Surface(
                modifier = Modifier.size(8.dp),
                shape = CircleShape,
                color = endColor,
            ) {}
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = "End",
                style = MaterialTheme.typography.labelSmall,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Empty route view
// ---------------------------------------------------------------------------

@Composable
private fun EmptyRouteView(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "No route data available",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
        )
    }
}

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

private data class RouteBounds(
    val minLat: Double,
    val maxLat: Double,
    val minLon: Double,
    val maxLon: Double,
)

private fun computeBounds(points: List<RoutePoint>): RouteBounds {
    var minLat = Double.MAX_VALUE
    var maxLat = -Double.MAX_VALUE
    var minLon = Double.MAX_VALUE
    var maxLon = -Double.MAX_VALUE

    for (point in points) {
        minLat = min(minLat, point.latitude)
        maxLat = max(maxLat, point.latitude)
        minLon = min(minLon, point.longitude)
        maxLon = max(maxLon, point.longitude)
    }

    // Add small padding to bounds
    val latPad = max((maxLat - minLat) * 0.1, 0.0005)
    val lonPad = max((maxLon - minLon) * 0.1, 0.0005)

    return RouteBounds(
        minLat = minLat - latPad,
        maxLat = maxLat + latPad,
        minLon = minLon - lonPad,
        maxLon = maxLon + lonPad,
    )
}

private fun findNearestPoint(
    tapOffset: Offset,
    routePoints: List<RoutePoint>,
    bounds: RouteBounds,
    canvasSize: Size,
    scale: Float,
    panOffsetX: Float,
    panOffsetY: Float,
): RoutePoint? {
    val padding = 40f
    val effectiveWidth = (canvasSize.width - 2 * padding) * scale
    val effectiveHeight = (canvasSize.height - 2 * padding) * scale

    val latRange = bounds.maxLat - bounds.minLat
    val lonRange = bounds.maxLon - bounds.minLon
    val latMid = (bounds.minLat + bounds.maxLat) / 2.0
    val cosLat = cos(Math.toRadians(latMid))
    val adjustedLonRange = lonRange * cosLat

    val dataAspect = if (latRange > 0 && adjustedLonRange > 0) {
        adjustedLonRange / latRange
    } else {
        1.0
    }
    val canvasAspect = effectiveWidth / effectiveHeight

    val scaleX: Float
    val scaleY: Float
    val drawOffsetX: Float
    val drawOffsetY: Float

    if (dataAspect > canvasAspect) {
        scaleX = effectiveWidth
        scaleY = (effectiveWidth / dataAspect).toFloat()
        drawOffsetX = padding + panOffsetX
        drawOffsetY = padding + (effectiveHeight - scaleY) / 2f + panOffsetY
    } else {
        scaleY = effectiveHeight
        scaleX = (effectiveHeight * dataAspect).toFloat()
        drawOffsetX = padding + (effectiveWidth - scaleX) / 2f + panOffsetX
        drawOffsetY = padding + panOffsetY
    }

    var nearest: RoutePoint? = null
    var minDist = Float.MAX_VALUE
    val threshold = 30f // tap tolerance in pixels

    for (point in routePoints) {
        val x = if (lonRange > 0) {
            ((point.longitude - bounds.minLon) * cosLat / (lonRange * cosLat) * scaleX).toFloat()
        } else {
            scaleX / 2f
        }
        val y = if (latRange > 0) {
            ((1.0 - (point.latitude - bounds.minLat) / latRange) * scaleY).toFloat()
        } else {
            scaleY / 2f
        }
        val screenX = drawOffsetX + x
        val screenY = drawOffsetY + y

        val dx = tapOffset.x - screenX
        val dy = tapOffset.y - screenY
        val dist = sqrt(dx * dx + dy * dy)

        if (dist < minDist && dist < threshold) {
            minDist = dist
            nearest = point
        }
    }

    return nearest
}

private fun DrawScope.drawGrid(color: Color, padding: Float) {
    val step = 50f
    var x = padding
    while (x < size.width - padding) {
        drawLine(color, Offset(x, padding), Offset(x, size.height - padding), strokeWidth = 0.5f)
        x += step
    }
    var y = padding
    while (y < size.height - padding) {
        drawLine(color, Offset(padding, y), Offset(size.width - padding, y), strokeWidth = 0.5f)
        y += step
    }
}

/**
 * KMP-compatible decimal formatting.
 * Formats a [Double] to the specified number of [decimals].
 */
internal fun formatDecimal(value: Double, decimals: Int): String {
    val factor = pow10(decimals)
    val rounded = (value * factor).roundToLong().toDouble() / factor
    val parts = rounded.toString().split(".")
    val intPart = parts[0]
    val fracPart = if (parts.size > 1) parts[1] else ""
    return if (decimals > 0) {
        "$intPart.${fracPart.padEnd(decimals, '0').take(decimals)}"
    } else {
        intPart
    }
}

private fun pow10(n: Int): Long {
    var result = 1L
    repeat(n) { result *= 10L }
    return result
}

private data class DisplayRouteSegment(
    val from: RoutePoint,
    val to: RoutePoint,
    val type: JoggingSegmentType,
)

private fun buildDisplaySegments(
    routePoints: List<RoutePoint>,
    segments: List<JoggingSegment>,
): List<DisplayRouteSegment> {
    if (routePoints.size < 2) return emptyList()

    val sortedSegments = segments
        .sortedBy { it.startedAt }
        .filter { it.endedAt != null }

    return buildList {
        for (index in 0 until routePoints.lastIndex) {
            val from = routePoints[index]
            val to = routePoints[index + 1]
            add(
                DisplayRouteSegment(
                    from = from,
                    to = to,
                    type = resolveSegmentType(
                        midpoint = midpoint(from.timestamp, to.timestamp),
                        segments = sortedSegments,
                    ),
                ),
            )
        }
    }
}

private fun resolveSegmentType(
    midpoint: Instant,
    segments: List<JoggingSegment>,
): JoggingSegmentType {
    val matched = segments.firstOrNull { segment ->
        val end = segment.endedAt ?: return@firstOrNull false
        midpoint >= segment.startedAt && midpoint <= end
    }
    return matched?.type ?: JoggingSegmentType.RUN
}

private fun midpoint(start: Instant, end: Instant): Instant {
    val midpointMillis = (start.toEpochMilliseconds() + end.toEpochMilliseconds()) / 2L
    return Instant.fromEpochMilliseconds(midpointMillis)
}
