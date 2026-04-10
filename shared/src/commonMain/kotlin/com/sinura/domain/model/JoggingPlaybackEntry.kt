package com.sinura.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

@Serializable
data class JoggingPlaybackEntry(
    val id: String,
    val sessionId: String,
    val source: String,
    val trackTitle: String,
    val artistName: String? = null,
    val spotifyTrackUri: String? = null,
    val startedAt: Instant,
    val endedAt: Instant,
    val startDistanceMeters: Double = 0.0,
    val endDistanceMeters: Double = 0.0,
    val startActiveDurationSeconds: Long = 0,
    val endActiveDurationSeconds: Long = 0,
) {
    init {
        require(id.isNotBlank()) { "JoggingPlaybackEntry.id must not be blank" }
        require(sessionId.isNotBlank()) { "JoggingPlaybackEntry.sessionId must not be blank" }
        require(source.isNotBlank()) { "JoggingPlaybackEntry.source must not be blank" }
        require(trackTitle.isNotBlank()) { "JoggingPlaybackEntry.trackTitle must not be blank" }
        require(startDistanceMeters >= 0.0) { "JoggingPlaybackEntry.startDistanceMeters must be >= 0" }
        require(endDistanceMeters >= 0.0) { "JoggingPlaybackEntry.endDistanceMeters must be >= 0" }
        require(startActiveDurationSeconds >= 0) { "JoggingPlaybackEntry.startActiveDurationSeconds must be >= 0" }
        require(endActiveDurationSeconds >= 0) { "JoggingPlaybackEntry.endActiveDurationSeconds must be >= 0" }
        require(endedAt >= startedAt) { "JoggingPlaybackEntry.endedAt must not precede startedAt" }
    }
}
