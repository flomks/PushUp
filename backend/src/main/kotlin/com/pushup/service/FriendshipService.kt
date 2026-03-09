package com.pushup.service

import com.pushup.models.FriendshipResponse
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
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.UUID

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
 * Business logic for the friends feature.
 *
 * All database access is performed inside [newSuspendedTransaction] so that
 * Ktor's coroutine event loop is not blocked.
 */
class FriendshipService {

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
    suspend fun sendFriendRequest(
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
}
