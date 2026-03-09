package com.pushup.service

import com.pushup.models.FriendProfile
import com.pushup.models.FriendshipResponse
import com.pushup.models.FriendsListResponse
import com.pushup.plugins.FriendshipStatus
import com.pushup.plugins.Friendships
import com.pushup.plugins.NotificationType
import com.pushup.plugins.Notifications
import com.pushup.plugins.Users
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.and
import org.jetbrains.exposed.sql.insert
import org.jetbrains.exposed.sql.or
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import org.jetbrains.exposed.sql.update
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.UUID

/**
 * Filter applied to GET /api/friends.
 *
 *   ACCEPTED -- users who are confirmed friends (status = accepted)
 *   INCOMING -- pending requests where the caller is the receiver
 *   OUTGOING -- pending requests where the caller is the requester
 */
enum class FriendListFilter {
    ACCEPTED,
    INCOMING,
    OUTGOING,
    ;

    companion object {
        /**
         * Parses the `?status=` query parameter value (case-insensitive).
         * Returns null when the value is unrecognised.
         */
        fun fromQueryParam(value: String?): FriendListFilter? = when (value?.lowercase()) {
            null, "", "accepted" -> ACCEPTED
            "incoming"           -> INCOMING
            "outgoing"           -> OUTGOING
            else                 -> null
        }
    }
}

/**
 * Result type for [FriendshipService.sendFriendRequest].
 *
 * Using a sealed class instead of exceptions keeps error handling explicit and
 * avoids leaking database details through uncaught exceptions.
 */
sealed class SendFriendRequestResult {
    /** The request was created successfully. */
    data class Success(val friendship: FriendshipResponse) : SendFriendRequestResult()

    /** The requester tried to send a request to themselves. */
    object SelfRequest : SendFriendRequestResult()

    /** The receiver does not exist in the users table. */
    object ReceiverNotFound : SendFriendRequestResult()

    /**
     * A friendship row already exists between the two users in either direction.
     * [existingStatus] is the current status of that row.
     */
    data class AlreadyExists(val existingStatus: String) : SendFriendRequestResult()
}

/**
 * Result type for [FriendshipService.respondToFriendRequest].
 *
 * Using a sealed class instead of exceptions keeps error handling explicit and
 * avoids leaking database details through uncaught exceptions.
 */
sealed class RespondFriendRequestResult {
    /** The status was updated successfully. */
    data class Success(val friendship: FriendshipResponse) : RespondFriendRequestResult()

    /** No friendship row with the given ID exists. */
    object NotFound : RespondFriendRequestResult()

    /**
     * The caller is not the receiver of the request and therefore is not
     * allowed to accept or decline it.
     */
    object Forbidden : RespondFriendRequestResult()

    /**
     * The friendship is no longer in the `pending` state and cannot be
     * changed again (it was already accepted or declined).
     */
    data class AlreadyResponded(val currentStatus: String) : RespondFriendRequestResult()
}

/**
 * Business logic for the friends feature.
 *
 * All database access is performed inside [newSuspendedTransaction] so that
 * Ktor's coroutine event loop is not blocked.
 *
 * The class and its public methods are `open` so that tests can create stub
 * subclasses without requiring a mocking framework.
 */
open class FriendshipService {

    /**
     * Sends a friend request from [requesterId] to [receiverId].
     *
     * Validation rules (checked in order):
     * 1. [requesterId] must not equal [receiverId] (no self-requests).
     * 2. [receiverId] must exist in the `users` table.
     * 3. No existing friendship row must exist between the two users in either
     *    direction (regardless of status -- pending, accepted, or declined).
     *
     * On success, a new row is inserted into `friendships` with status `pending`
     * and an in-app notification is created for the receiver.
     *
     * @return [SendFriendRequestResult] describing the outcome.
     */
    open suspend fun sendFriendRequest(
        requesterId: UUID,
        receiverId: UUID,
    ): SendFriendRequestResult = newSuspendedTransaction {

        // ------------------------------------------------------------------
        // 1. Self-request guard
        // ------------------------------------------------------------------
        if (requesterId == receiverId) {
            return@newSuspendedTransaction SendFriendRequestResult.SelfRequest
        }

        // ------------------------------------------------------------------
        // 2. Verify the receiver exists
        // ------------------------------------------------------------------
        val receiverExists = Users.selectAll()
            .where { Users.id eq receiverId }
            .count() > 0

        if (!receiverExists) {
            return@newSuspendedTransaction SendFriendRequestResult.ReceiverNotFound
        }

        // ------------------------------------------------------------------
        // 3. Check for an existing friendship row in either direction
        //    (A->B or B->A) regardless of status.
        // ------------------------------------------------------------------
        val existingRow = Friendships.selectAll()
            .where {
                (
                    (Friendships.requesterId eq requesterId) and
                        (Friendships.receiverId eq receiverId)
                ) or (
                    (Friendships.requesterId eq receiverId) and
                        (Friendships.receiverId eq requesterId)
                )
            }
            .singleOrNull()

        if (existingRow != null) {
            val status = existingRow[Friendships.status]
            return@newSuspendedTransaction SendFriendRequestResult.AlreadyExists(status)
        }

        // ------------------------------------------------------------------
        // 4. Insert the new friendship row with status = pending
        // ------------------------------------------------------------------
        val newId = UUID.randomUUID()
        val now = OffsetDateTime.now()

        Friendships.insert {
            it[id]          = newId
            it[Friendships.requesterId] = requesterId
            it[Friendships.receiverId]  = receiverId
            it[status]      = FriendshipStatus.PENDING.toDbValue()
            it[createdAt]   = now
            it[updatedAt]   = now
        }

        // ------------------------------------------------------------------
        // 5. Create an in-app notification for the receiver
        // ------------------------------------------------------------------
        Notifications.insert {
            it[id]        = UUID.randomUUID()
            it[userId]    = receiverId
            it[type]      = NotificationType.FRIEND_REQUEST.toDbValue()
            it[actorId]   = requesterId
            it[payload]   = """{"friendship_id":"$newId"}"""
            it[isRead]    = false
            it[createdAt] = now
            it[updatedAt] = now
        }

        // ------------------------------------------------------------------
        // 6. Return the created friendship
        // ------------------------------------------------------------------
        SendFriendRequestResult.Success(
            FriendshipResponse(
                id          = newId.toString(),
                requesterId = requesterId.toString(),
                receiverId  = receiverId.toString(),
                status      = FriendshipStatus.PENDING.toDbValue(),
                createdAt   = now.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
            ),
        )
    }

    /**
     * Allows the receiver of a friend request to accept or decline it.
     *
     * Validation rules (checked in order):
     * 1. A friendship row with [friendshipId] must exist.
     * 2. [callerId] must be the `receiver_id` of that row (only the receiver
     *    may respond -- the requester gets a 403 otherwise).
     * 3. The current status must be `pending` (already-answered requests are
     *    immutable).
     *
     * On success:
     * - The `status` column is updated to [newStatus] and `updated_at` is
     *   refreshed.
     * - If [newStatus] is `accepted`, an in-app notification of type
     *   `friend_accepted` is created for the original requester.
     *
     * @param callerId     UUID of the authenticated user making the request.
     * @param friendshipId UUID of the friendship row to update.
     * @param newStatus    The desired new status -- must be [FriendshipStatus.ACCEPTED]
     *                     or [FriendshipStatus.DECLINED].
     * @return [RespondFriendRequestResult] describing the outcome.
     */
    open suspend fun respondToFriendRequest(
        callerId: UUID,
        friendshipId: UUID,
        newStatus: FriendshipStatus,
    ): RespondFriendRequestResult = newSuspendedTransaction {

        // ------------------------------------------------------------------
        // 1. Look up the friendship row
        // ------------------------------------------------------------------
        val row = Friendships.selectAll()
            .where { Friendships.id eq friendshipId }
            .singleOrNull()
            ?: return@newSuspendedTransaction RespondFriendRequestResult.NotFound

        val rowReceiverId  = row[Friendships.receiverId]
        val rowRequesterId = row[Friendships.requesterId]
        val currentStatus  = row[Friendships.status]
        val createdAt      = row[Friendships.createdAt]

        // ------------------------------------------------------------------
        // 2. Only the receiver may respond
        // ------------------------------------------------------------------
        if (callerId != rowReceiverId) {
            return@newSuspendedTransaction RespondFriendRequestResult.Forbidden
        }

        // ------------------------------------------------------------------
        // 3. Only pending requests can be answered
        // ------------------------------------------------------------------
        if (currentStatus != FriendshipStatus.PENDING.toDbValue()) {
            return@newSuspendedTransaction RespondFriendRequestResult.AlreadyResponded(currentStatus)
        }

        // ------------------------------------------------------------------
        // 4. Update the status
        // ------------------------------------------------------------------
        val now = OffsetDateTime.now()

        Friendships.update({ Friendships.id eq friendshipId }) {
            it[status]    = newStatus.toDbValue()
            it[updatedAt] = now
        }

        // ------------------------------------------------------------------
        // 5. Notify the requester when the request is accepted
        // ------------------------------------------------------------------
        if (newStatus == FriendshipStatus.ACCEPTED) {
            Notifications.insert {
                it[id]        = UUID.randomUUID()
                it[userId]    = rowRequesterId
                it[type]      = NotificationType.FRIEND_ACCEPTED.toDbValue()
                it[actorId]   = callerId
                it[payload]   = """{"friendship_id":"$friendshipId"}"""
                it[isRead]    = false
                it[Notifications.createdAt] = now
                it[updatedAt] = now
            }
        }

        // ------------------------------------------------------------------
        // 6. Return the updated friendship
        // ------------------------------------------------------------------
        RespondFriendRequestResult.Success(
            FriendshipResponse(
                id          = friendshipId.toString(),
                requesterId = rowRequesterId.toString(),
                receiverId  = rowReceiverId.toString(),
                status      = newStatus.toDbValue(),
                createdAt   = createdAt.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
            ),
        )
    }

    /**
     * Returns the friends list for [userId] filtered by [filter].
     *
     * - [FriendListFilter.ACCEPTED]  -- all users who share an `accepted`
     *   friendship row with [userId] (in either direction).
     * - [FriendListFilter.INCOMING]  -- users who sent a `pending` request to
     *   [userId] (i.e. [userId] is the receiver).
     * - [FriendListFilter.OUTGOING]  -- users to whom [userId] sent a `pending`
     *   request (i.e. [userId] is the requester).
     *
     * Each entry contains the basic profile data of the counterpart user:
     * id, username, displayName, avatarUrl.
     *
     * @param userId UUID of the authenticated caller.
     * @param filter Which subset of relationships to return.
     * @return [FriendsListResponse] with the matching profiles.
     */
    open suspend fun getFriends(
        userId: UUID,
        filter: FriendListFilter,
    ): FriendsListResponse = newSuspendedTransaction {

        // ------------------------------------------------------------------
        // Build the WHERE predicate based on the requested filter.
        //
        // For ACCEPTED we look in both directions (A->B or B->A) because
        // either party could have been the original requester.
        // For INCOMING / OUTGOING the direction is fixed.
        // ------------------------------------------------------------------
        val rows = when (filter) {
            FriendListFilter.ACCEPTED -> Friendships.selectAll().where {
                (Friendships.status eq FriendshipStatus.ACCEPTED.toDbValue()) and (
                    (Friendships.requesterId eq userId) or
                    (Friendships.receiverId  eq userId)
                )
            }

            FriendListFilter.INCOMING -> Friendships.selectAll().where {
                (Friendships.status     eq FriendshipStatus.PENDING.toDbValue()) and
                (Friendships.receiverId eq userId)
            }

            FriendListFilter.OUTGOING -> Friendships.selectAll().where {
                (Friendships.status      eq FriendshipStatus.PENDING.toDbValue()) and
                (Friendships.requesterId eq userId)
            }
        }.toList()

        // ------------------------------------------------------------------
        // For each friendship row, determine the UUID of the counterpart
        // (the "other" user), then fetch their profile from the users table.
        // ------------------------------------------------------------------
        val counterpartIds: List<UUID> = rows.map { row ->
            val requesterId = row[Friendships.requesterId]
            val receiverId  = row[Friendships.receiverId]
            if (requesterId == userId) receiverId else requesterId
        }

        // Fetch all counterpart profiles in a single query.
        val profilesById: Map<UUID, FriendProfile> = if (counterpartIds.isEmpty()) {
            emptyMap()
        } else {
            Users.selectAll()
                .where { Users.id inList counterpartIds }
                .associate { userRow ->
                    val id = userRow[Users.id]
                    id to FriendProfile(
                        id          = id.toString(),
                        username    = userRow[Users.username],
                        displayName = userRow[Users.displayName],
                        avatarUrl   = userRow[Users.avatarUrl],
                    )
                }
        }

        // Preserve the order returned by the friendship query.
        val friends: List<FriendProfile> = counterpartIds.mapNotNull { profilesById[it] }

        FriendsListResponse(friends = friends, total = friends.size)
    }
}
