package com.pushup.service

import com.pushup.models.FriendshipStatusResponse
import com.pushup.models.UserSearchResponse
import com.pushup.models.UserSearchResult
import com.pushup.plugins.FriendshipStatus
import com.pushup.plugins.Friendships
import com.pushup.plugins.Users
import org.jetbrains.exposed.sql.Op
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.like
import org.jetbrains.exposed.sql.and
import org.jetbrains.exposed.sql.lowerCase
import org.jetbrains.exposed.sql.or
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import java.util.UUID

/**
 * Handles user search queries for the GET /api/users/search endpoint.
 *
 * Search behaviour:
 * - Matches against [Users.username] and [Users.displayName] using a
 *   case-insensitive prefix/substring search (SQL ILIKE with leading wildcard).
 * - The authenticated caller is always excluded from the results.
 * - Each result is annotated with the friendship status between the caller
 *   and the matched user:
 *     - [FriendshipStatusResponse.friend]  -- accepted friendship exists
 *     - [FriendshipStatusResponse.pending] -- a pending request exists in
 *                                             either direction
 *     - [FriendshipStatusResponse.none]    -- no relationship
 * - Blocked users (status = DECLINED) are excluded from the results entirely.
 * - Results are capped at [MAX_RESULTS] entries.
 *
 * All database access is performed inside a single suspended transaction so
 * the coroutine does not block a thread.
 */
open class UserSearchService {

    companion object {
        /** Maximum number of results returned per query. */
        const val MAX_RESULTS = 20

        /** Minimum query length enforced at the service layer as a safety net. */
        const val MIN_QUERY_LENGTH = 2
    }

    /**
     * Searches for users whose [Users.username] or [Users.displayName] contains
     * [query] (case-insensitive).
     *
     * @param query      The search term supplied by the client (already validated
     *                   to be at least [MIN_QUERY_LENGTH] characters by the route
     *                   handler; the service re-validates as a safety net).
     * @param callerId   UUID of the authenticated user making the request.
     *                   This user is excluded from the results.
     * @return           [UserSearchResponse] with up to [MAX_RESULTS] entries.
     * @throws IllegalArgumentException if [query] is shorter than [MIN_QUERY_LENGTH].
     */
    open suspend fun search(query: String, callerId: UUID): UserSearchResponse {
        require(query.length >= MIN_QUERY_LENGTH) {
            "Search query must be at least $MIN_QUERY_LENGTH characters long"
        }

        // SQL ILIKE pattern: '%<query>%' -- matches anywhere in the value.
        // Both sides are lowercased so the comparison is truly case-insensitive
        // regardless of the database collation.
        val pattern = "%${query.lowercase()}%"

        return newSuspendedTransaction {

            // ------------------------------------------------------------------
            // 1. Fetch all friendship rows that involve the caller so we can
            //    annotate results without issuing N+1 queries.
            // ------------------------------------------------------------------
            val friendshipRows = Friendships.selectAll()
                .where {
                    (Friendships.requesterId eq callerId) or
                        (Friendships.receiverId eq callerId)
                }
                .toList()

            // Build a map: otherUserId -> FriendshipStatus for fast lookup.
            val friendshipByPeer: Map<UUID, FriendshipStatus> = friendshipRows.associate { row ->
                val peerId = if (row[Friendships.requesterId] == callerId) {
                    row[Friendships.receiverId]
                } else {
                    row[Friendships.requesterId]
                }
                peerId to FriendshipStatus.fromDbValue(row[Friendships.status])
            }

            // Collect the IDs of users the caller has DECLINED (blocked) so
            // they can be excluded from search results.
            val excludedIds: Set<UUID> = friendshipByPeer
                .filterValues { it == FriendshipStatus.DECLINED }
                .keys

            // ------------------------------------------------------------------
            // 2. Query users matching the search term.
            //    Exclude: the caller themselves, and any blocked users.
            // ------------------------------------------------------------------
            val userRows = Users.selectAll()
                .where {
                    // Match username OR display_name (case-insensitive)
                    val matchesQuery: Op<Boolean> =
                        (Users.username.lowerCase() like pattern) or
                            (Users.displayName.lowerCase() like pattern)

                    // Exclude the caller
                    val notSelf: Op<Boolean> = Users.id neq callerId

                    // Exclude blocked peers
                    val notBlocked: Op<Boolean> = if (excludedIds.isEmpty()) {
                        Op.TRUE
                    } else {
                        Users.id notInList excludedIds
                    }

                    matchesQuery and notSelf and notBlocked
                }
                .limit(MAX_RESULTS)
                .toList()

            // ------------------------------------------------------------------
            // 3. Map rows to response DTOs, annotating each with friendship status.
            // ------------------------------------------------------------------
            val results = userRows.map { row ->
                val userId = row[Users.id]
                val status = when (friendshipByPeer[userId]) {
                    FriendshipStatus.ACCEPTED -> FriendshipStatusResponse.friend
                    FriendshipStatus.PENDING  -> FriendshipStatusResponse.pending
                    else                      -> FriendshipStatusResponse.none
                }
                UserSearchResult(
                    id               = userId.toString(),
                    username         = row[Users.username],
                    displayName      = row[Users.displayName],
                    avatarUrl        = row[Users.avatarUrl],
                    friendshipStatus = status,
                )
            }

            UserSearchResponse(
                results = results,
                total   = results.size,
            )
        }
    }
}
