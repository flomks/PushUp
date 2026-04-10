package com.sinura.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Represents the synchronization state of a domain entity
 * with the remote backend.
 *
 * Explicit [SerialName] annotations guarantee a stable wire format
 * that is decoupled from Kotlin identifier refactoring.
 */
@Serializable
enum class SyncStatus {

    /** Successfully synchronized with the server. */
    @SerialName("synced")
    SYNCED,

    /** Changes exist locally that have not yet been pushed to the server. */
    @SerialName("pending")
    PENDING,

    /** The last synchronization attempt failed. */
    @SerialName("failed")
    FAILED,
}
