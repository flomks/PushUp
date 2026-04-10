package com.sinura.service

import com.sinura.plugins.DeviceTokens
import com.sinura.plugins.Users
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.deleteWhere
import org.jetbrains.exposed.sql.insert
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import org.jetbrains.exposed.sql.update
import java.time.OffsetDateTime
import java.util.UUID

/**
 * Thrown by [DeviceTokenService.upsertToken] when the [userId] does not exist
 * in the [Users] table.
 *
 * This happens when a user has been deleted from Supabase but the iOS app
 * still holds a valid JWT and attempts to register a device token. The route
 * handler catches this and returns 404 instead of letting the foreign-key
 * violation propagate as a 500.
 */
class UserNotFoundException(userId: UUID) :
    Exception("User not found: $userId")

/**
 * Manages APNs (and future FCM) device tokens for push notification delivery.
 *
 * Each user may have multiple tokens (one per device). Tokens are upserted
 * on every app launch so stale tokens are replaced automatically.
 *
 * The class is `open` so tests can create stub subclasses.
 */
open class DeviceTokenService {

    /**
     * Registers or updates a device token for [userId].
     *
     * If a row with the same [token] already exists for this user, its
     * [updatedAt] timestamp is refreshed. If the token belongs to a different
     * user (device hand-off), the old row is re-assigned to the new user.
     *
     * @param userId   UUID of the authenticated user.
     * @param token    The APNs device token hex string.
     * @param platform "apns" for iOS, "fcm" for Android (reserved).
     * @throws UserNotFoundException if [userId] does not exist in the users table.
     *   This occurs when a user has been deleted from Supabase but the device
     *   still holds a valid JWT. The caller should return 404 to the client.
     */
    open suspend fun upsertToken(
        userId: UUID,
        token: String,
        platform: String = "apns",
    ): Unit = newSuspendedTransaction {
        val now = OffsetDateTime.now()

        // Guard: verify the user exists before touching device_tokens.
        // Without this check, the INSERT below would throw a PostgreSQL
        // foreign-key violation (23503) when the user row has been deleted
        // (e.g. all users cleared in the Supabase dashboard) while the device
        // still holds a valid JWT. We surface this as a typed exception so the
        // route handler can return 404 instead of 500.
        val userExists = Users.selectAll()
            .where { Users.id eq userId }
            .count() > 0

        if (!userExists) {
            throw UserNotFoundException(userId)
        }

        // Check if this exact token already exists (for any user).
        val existing = DeviceTokens.selectAll()
            .where { DeviceTokens.token eq token }
            .singleOrNull()

        when {
            existing == null -> {
                // New token -- insert a fresh row.
                DeviceTokens.insert {
                    it[id]                    = UUID.randomUUID()
                    it[DeviceTokens.userId]   = userId
                    it[DeviceTokens.token]    = token
                    it[DeviceTokens.platform] = platform
                    it[createdAt]             = now
                    it[updatedAt]             = now
                }
            }

            existing[DeviceTokens.userId] == userId -> {
                // Same user, same token -- just refresh the timestamp.
                DeviceTokens.update({ DeviceTokens.token eq token }) {
                    it[updatedAt] = now
                }
            }

            else -> {
                // Token transferred to a new user (device hand-off) -- re-assign.
                DeviceTokens.update({ DeviceTokens.token eq token }) {
                    it[DeviceTokens.userId] = userId
                    it[updatedAt]           = now
                }
            }
        }
    }

    /**
     * Returns all active device tokens for [userId].
     *
     * @param userId UUID of the user whose tokens to retrieve.
     * @return List of token strings (may be empty if the user has no registered devices).
     */
    open suspend fun getTokensForUser(userId: UUID): List<String> =
        newSuspendedTransaction {
            DeviceTokens.selectAll()
                .where { DeviceTokens.userId eq userId }
                .map { it[DeviceTokens.token] }
        }

    /**
     * Removes a specific device token (e.g. on logout or when APNs reports
     * the token as invalid).
     *
     * @param token The token to remove.
     */
    open suspend fun removeToken(token: String): Unit = newSuspendedTransaction {
        DeviceTokens.deleteWhere { DeviceTokens.token eq token }
    }

    /**
     * Removes all device tokens for [userId] (e.g. on account deletion).
     *
     * @param userId UUID of the user whose tokens to remove.
     */
    open suspend fun removeAllTokensForUser(userId: UUID): Unit = newSuspendedTransaction {
        DeviceTokens.deleteWhere { DeviceTokens.userId eq userId }
    }
}
