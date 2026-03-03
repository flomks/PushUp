package com.pushup.domain.usecase

import kotlin.random.Random

/**
 * Strategy interface for generating unique string identifiers.
 *
 * Abstracting ID generation behind an interface allows use-cases to remain
 * deterministic in tests (by injecting a fixed or sequential generator)
 * while using a random UUID-like generator in production.
 */
fun interface IdGenerator {
    /** Returns a new unique identifier string. */
    fun generate(): String
}

/**
 * Default production [IdGenerator] that produces random UUID v4-like strings.
 *
 * Uses [kotlin.random.Random] so it works on all KMP targets without
 * requiring platform-specific `java.util.UUID` or NSUUID.
 *
 * Format: `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`
 * where `x` is a random hex digit, the version nibble is always `4`,
 * and the variant nibble `y` is one of `8`, `9`, `a`, or `b`.
 */
object DefaultIdGenerator : IdGenerator {
    private val hex = "0123456789abcdef"

    override fun generate(): String {
        // Build 16 random bytes, then format as UUID v4
        val bytes = ByteArray(16) { Random.nextInt(256).toByte() }
        // Set version to 4 (bits 12-15 of time_hi_and_version)
        bytes[6] = ((bytes[6].toInt() and 0x0F) or 0x40).toByte()
        // Set variant to 10xx (RFC 4122)
        bytes[8] = ((bytes[8].toInt() and 0x3F) or 0x80).toByte()

        return buildString(36) {
            bytes.forEachIndexed { i, byte ->
                if (i == 4 || i == 6 || i == 8 || i == 10) append('-')
                val v = byte.toInt() and 0xFF
                append(hex[v ushr 4])
                append(hex[v and 0x0F])
            }
        }
    }
}
