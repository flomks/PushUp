package com.pushup.service

import com.pushup.models.FriendCodeResponse
import com.pushup.models.FriendProfile
import com.pushup.models.FriendshipResponse
import com.pushup.models.UseFriendCodeResponse
import com.pushup.plugins.FriendCodePrivacy
import com.pushup.plugins.FriendCodes
import com.pushup.plugins.FriendshipStatus
import com.pushup.plugins.Friendships
import com.pushup.plugins.Users
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.and
import org.jetbrains.exposed.sql.deleteWhere
import org.jetbrains.exposed.sql.insert
import org.jetbrains.exposed.sql.or
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import org.jetbrains.exposed.sql.update
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.UUID

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

sealed class GetOrCreateFriendCodeResult {
    data class Success(val response: FriendCodeResponse) : GetOrCreateFriendCodeResult()
    object UserNotFound : GetOrCreateFriendCodeResult()
}

sealed class UpdatePrivacyResult {
    data class Success(val response: FriendCodeResponse) : UpdatePrivacyResult()
    object NotFound : UpdatePrivacyResult()
    data class InvalidPrivacy(val value: String) : UpdatePrivacyResult()
}

sealed class ResetCodeResult {
    data class Success(val response: FriendCodeResponse) : ResetCodeResult()
    object UserNotFound : ResetCodeResult()
}

sealed class UseFriendCodeResult {
    /** The caller was added as a friend immediately (auto_accept). */
    data class Added(val response: UseFriendCodeResponse) : UseFriendCodeResult()

    /** A pending friend request was created (require_approval). */
    data class Pending(val response: UseFriendCodeResponse) : UseFriendCodeResult()

    /** The code does not exist. */
    object CodeNotFound : UseFriendCodeResult()

    /** The code's privacy is set to inactive. */
    object CodeInactive : UseFriendCodeResult()

    /** The caller tried to use their own code. */
    object SelfUse : UseFriendCodeResult()

    /** The caller is already friends with the code owner. */
    data class AlreadyFriends(val existingStatus: String) : UseFriendCodeResult()
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/**
 * Business logic for the friend code feature.
 *
 * Each user has at most one friend code row. The code is generated on first
 * access and can be reset (new random value) or deactivated via the privacy
 * setting.
 *
 * Deep-link format: `pushup://friend-code/<CODE>`
 */
open class FriendCodeService(
    private val deviceTokenService: DeviceTokenService = DeviceTokenService(),
) {

    companion object {
        private const val DEEP_LINK_BASE = "https://pushup.weareo.fun/friend"
        private val CHARSET = ('A'..'Z') + ('0'..'9')

        /** Generates a random 8-character uppercase alphanumeric code. */
        fun generateCode(length: Int = 8): String =
            (1..length).map { CHARSET.random() }.joinToString("")
    }

    // -------------------------------------------------------------------------
    // Get or create the caller's friend code
    // -------------------------------------------------------------------------

    /**
     * Returns the authenticated user's friend code, creating one if it does not
     * yet exist (with default privacy = require_approval).
     */
    open suspend fun getOrCreateFriendCode(userId: UUID): GetOrCreateFriendCodeResult =
        newSuspendedTransaction {
            // Verify user exists
            val userExists = Users.selectAll().where { Users.id eq userId }.count() > 0
            if (!userExists) return@newSuspendedTransaction GetOrCreateFriendCodeResult.UserNotFound

            val existing = FriendCodes.selectAll()
                .where { FriendCodes.userId eq userId }
                .singleOrNull()

            if (existing != null) {
                return@newSuspendedTransaction GetOrCreateFriendCodeResult.Success(
                    existing.toResponse(),
                )
            }

            // Create a new code, retrying on collision (extremely unlikely).
            val code = generateUniqueCode()
            val now  = OffsetDateTime.now()
            val newId = UUID.randomUUID()

            FriendCodes.insert {
                it[id]        = newId
                it[FriendCodes.userId]  = userId
                it[FriendCodes.code]    = code
                it[privacy]   = FriendCodePrivacy.REQUIRE_APPROVAL
                it[createdAt] = now
                it[updatedAt] = now
            }

            GetOrCreateFriendCodeResult.Success(
                FriendCodeResponse(
                    code      = code,
                    privacy   = FriendCodePrivacy.REQUIRE_APPROVAL.pgValue,
                    deepLink  = "$DEEP_LINK_BASE/$code",
                    createdAt = now.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
                    updatedAt = now.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
                ),
            )
        }

    // -------------------------------------------------------------------------
    // Update privacy setting
    // -------------------------------------------------------------------------

    /**
     * Updates the privacy setting of the caller's friend code.
     *
     * @param userId  UUID of the authenticated caller.
     * @param privacy The desired new privacy value (string from request body).
     */
    open suspend fun updatePrivacy(userId: UUID, privacy: String): UpdatePrivacyResult {
        val newPrivacy = try {
            FriendCodePrivacy.fromDbValue(privacy)
        } catch (e: NoSuchElementException) {
            return UpdatePrivacyResult.InvalidPrivacy(privacy)
        }

        return newSuspendedTransaction {
            val row = FriendCodes.selectAll()
                .where { FriendCodes.userId eq userId }
                .singleOrNull()
                ?: return@newSuspendedTransaction UpdatePrivacyResult.NotFound

            val now = OffsetDateTime.now()
            FriendCodes.update({ FriendCodes.userId eq userId }) {
                it[FriendCodes.privacy]   = newPrivacy
                it[FriendCodes.updatedAt] = now
            }

            UpdatePrivacyResult.Success(
                FriendCodeResponse(
                    code      = row[FriendCodes.code],
                    privacy   = newPrivacy.pgValue,
                    deepLink  = "$DEEP_LINK_BASE/${row[FriendCodes.code]}",
                    createdAt = row[FriendCodes.createdAt].format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
                    updatedAt = now.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
                ),
            )
        }
    }

    // -------------------------------------------------------------------------
    // Reset code (generate a new random value)
    // -------------------------------------------------------------------------

    /**
     * Generates a new random code for the caller, replacing the existing one.
     * Creates the row if it does not yet exist.
     */
    open suspend fun resetCode(userId: UUID): ResetCodeResult =
        newSuspendedTransaction {
            val userExists = Users.selectAll().where { Users.id eq userId }.count() > 0
            if (!userExists) return@newSuspendedTransaction ResetCodeResult.UserNotFound

            val newCode = generateUniqueCode()
            val now     = OffsetDateTime.now()

            val existing = FriendCodes.selectAll()
                .where { FriendCodes.userId eq userId }
                .singleOrNull()

            if (existing != null) {
                FriendCodes.update({ FriendCodes.userId eq userId }) {
                    it[code]      = newCode
                    it[updatedAt] = now
                }
                ResetCodeResult.Success(
                    FriendCodeResponse(
                        code      = newCode,
                        privacy   = existing[FriendCodes.privacy].pgValue,
                        deepLink  = "$DEEP_LINK_BASE/$newCode",
                        createdAt = existing[FriendCodes.createdAt].format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
                        updatedAt = now.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
                    ),
                )
            } else {
                val newId = UUID.randomUUID()
                FriendCodes.insert {
                    it[id]        = newId
                    it[FriendCodes.userId]  = userId
                    it[code]      = newCode
                    it[privacy]   = FriendCodePrivacy.REQUIRE_APPROVAL
                    it[createdAt] = now
                    it[updatedAt] = now
                }
                ResetCodeResult.Success(
                    FriendCodeResponse(
                        code      = newCode,
                        privacy   = FriendCodePrivacy.REQUIRE_APPROVAL.pgValue,
                        deepLink  = "$DEEP_LINK_BASE/$newCode",
                        createdAt = now.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
                        updatedAt = now.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
                    ),
                )
            }
        }

    // -------------------------------------------------------------------------
    // Use a friend code
    // -------------------------------------------------------------------------

    /**
     * Processes a friend code entered or scanned by [callerId].
     *
     * Behaviour depends on the code owner's privacy setting:
     * - AUTO_ACCEPT      -> creates an accepted friendship immediately
     * - REQUIRE_APPROVAL -> creates a pending friend request
     * - INACTIVE         -> returns [UseFriendCodeResult.CodeInactive]
     *
     * Validation:
     * 1. Code must exist.
     * 2. Caller must not be the code owner.
     * 3. No existing friendship row between the two users.
     */
    open suspend fun useFriendCode(callerId: UUID, code: String): UseFriendCodeResult {
        val result = useFriendCodeInTransaction(callerId, code.uppercase().trim())

        // Fire push notifications outside the transaction (best-effort).
        when (result) {
            is UseFriendCodeResult.Added -> {
                val callerName = getDisplayName(callerId)
                val ownerId    = UUID.fromString(result.response.ownerProfile.id)
                val tokens     = deviceTokenService.getTokensForUser(ownerId)
                ApnsService.sendPushToAll(
                    deviceTokens = tokens,
                    title        = "New Friend",
                    body         = "$callerName added you via friend code.",
                    category     = "FRIEND_ACCEPTED",
                    data         = mapOf(
                        "type"       to "friend_code_added",
                        "caller_id"  to callerId.toString(),
                    ),
                )
            }
            is UseFriendCodeResult.Pending -> {
                val callerName = getDisplayName(callerId)
                val ownerId    = UUID.fromString(result.response.ownerProfile.id)
                val tokens     = deviceTokenService.getTokensForUser(ownerId)
                ApnsService.sendPushToAll(
                    deviceTokens = tokens,
                    title        = "New Friend Request",
                    body         = "$callerName sent you a friend request via friend code.",
                    category     = "FRIEND_REQUEST",
                    data         = mapOf(
                        "type"          to "friend_request",
                        "friendship_id" to result.response.friendship.id,
                        "requester_id"  to callerId.toString(),
                    ),
                )
            }
            else -> Unit
        }

        return result
    }

    private suspend fun useFriendCodeInTransaction(
        callerId: UUID,
        code: String,
    ): UseFriendCodeResult = newSuspendedTransaction {

        // 1. Look up the code row
        val codeRow = FriendCodes.selectAll()
            .where { FriendCodes.code eq code }
            .singleOrNull()
            ?: return@newSuspendedTransaction UseFriendCodeResult.CodeNotFound

        val ownerId = codeRow[FriendCodes.userId]
        val privacy = codeRow[FriendCodes.privacy]

        // 2. Self-use guard
        if (callerId == ownerId) {
            return@newSuspendedTransaction UseFriendCodeResult.SelfUse
        }

        // 3. Inactive guard
        if (privacy == FriendCodePrivacy.INACTIVE) {
            return@newSuspendedTransaction UseFriendCodeResult.CodeInactive
        }

        // 4. Check for existing friendship
        val existingRow = Friendships.selectAll().where {
            (
                (Friendships.requesterId eq callerId) and (Friendships.receiverId eq ownerId)
            ) or (
                (Friendships.requesterId eq ownerId) and (Friendships.receiverId eq callerId)
            )
        }.singleOrNull()

        if (existingRow != null) {
            val existingStatus = existingRow[Friendships.status]
            // Allow re-use if the previous request was declined (delete stale row).
            if (existingStatus != FriendshipStatus.DECLINED) {
                return@newSuspendedTransaction UseFriendCodeResult.AlreadyFriends(existingStatus.pgValue)
            }
            Friendships.deleteWhere { Friendships.id eq existingRow[Friendships.id] }
        }

        // 5. Fetch owner profile
        val ownerRow = Users.selectAll().where { Users.id eq ownerId }.singleOrNull()
        val ownerProfile = FriendProfile(
            id          = ownerId.toString(),
            username    = ownerRow?.get(Users.username),
            displayName = ownerRow?.get(Users.displayName),
            avatarUrl   = ownerRow?.let { Users.resolvedAvatarUrl(it) },
        )

        val now           = OffsetDateTime.now()
        val friendshipId  = UUID.randomUUID()

        when (privacy) {
            FriendCodePrivacy.AUTO_ACCEPT -> {
                // Insert directly as accepted
                Friendships.insert {
                    it[id]          = friendshipId
                    it[requesterId] = callerId
                    it[receiverId]  = ownerId
                    it[status]      = FriendshipStatus.ACCEPTED
                    it[createdAt]   = now
                    it[updatedAt]   = now
                }
                val friendship = FriendshipResponse(
                    id          = friendshipId.toString(),
                    requesterId = callerId.toString(),
                    receiverId  = ownerId.toString(),
                    status      = FriendshipStatus.ACCEPTED.pgValue,
                    createdAt   = now.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
                )
                UseFriendCodeResult.Added(
                    UseFriendCodeResponse(
                        result       = "added",
                        ownerProfile = ownerProfile,
                        friendship   = friendship,
                    ),
                )
            }

            FriendCodePrivacy.REQUIRE_APPROVAL -> {
                // Insert as pending (caller = requester, owner = receiver)
                Friendships.insert {
                    it[id]          = friendshipId
                    it[requesterId] = callerId
                    it[receiverId]  = ownerId
                    it[status]      = FriendshipStatus.PENDING
                    it[createdAt]   = now
                    it[updatedAt]   = now
                }
                val friendship = FriendshipResponse(
                    id          = friendshipId.toString(),
                    requesterId = callerId.toString(),
                    receiverId  = ownerId.toString(),
                    status      = FriendshipStatus.PENDING.pgValue,
                    createdAt   = now.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
                )
                UseFriendCodeResult.Pending(
                    UseFriendCodeResponse(
                        result       = "pending",
                        ownerProfile = ownerProfile,
                        friendship   = friendship,
                    ),
                )
            }

            FriendCodePrivacy.INACTIVE -> UseFriendCodeResult.CodeInactive
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /**
     * Generates a unique 8-character code, retrying up to 10 times on collision.
     * Must be called inside a transaction.
     */
    private fun generateUniqueCode(maxAttempts: Int = 10): String {
        repeat(maxAttempts) {
            val candidate = generateCode()
            val exists = FriendCodes.selectAll()
                .where { FriendCodes.code eq candidate }
                .count() > 0
            if (!exists) return candidate
        }
        // Extremely unlikely -- fall back to a longer code to guarantee uniqueness.
        return generateCode(12)
    }

    private suspend fun getDisplayName(userId: UUID): String =
        newSuspendedTransaction {
            Users.selectAll()
                .where { Users.id eq userId }
                .singleOrNull()
                ?.let { row -> row[Users.displayName] ?: row[Users.username] ?: "Someone" }
                ?: "Someone"
        }

    // -------------------------------------------------------------------------
    // Extension helper
    // -------------------------------------------------------------------------

    private fun org.jetbrains.exposed.sql.ResultRow.toResponse(): FriendCodeResponse =
        FriendCodeResponse(
            code      = this[FriendCodes.code],
            privacy   = this[FriendCodes.privacy].pgValue,
            deepLink  = "$DEEP_LINK_BASE/${this[FriendCodes.code]}",
            createdAt = this[FriendCodes.createdAt].format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
            updatedAt = this[FriendCodes.updatedAt].format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
        )
}
