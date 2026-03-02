package com.pushup.domain.model

import kotlinx.serialization.Serializable

/**
 * Represents the synchronization state of a domain entity
 * with the remote backend.
 */
@Serializable
enum class SyncStatus {
    /** Successfully synchronized with the server. */
    SYNCED,

    /** Changes exist locally that have not yet been pushed to the server. */
    PENDING,

    /** The last synchronization attempt failed. */
    FAILED,
}
