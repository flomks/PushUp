package com.pushup.service

import com.pushup.models.FriendshipStatusResponse
import com.pushup.models.UserSearchResponse
import com.pushup.models.UserSearchResult
import com.pushup.plugins.FriendshipStatus
import com.pushup.plugins.Friendships
import com.pushup.plugins.UserSettings
import com.pushup.plugins.Users
import org.jetbrains.exposed.sql.Op
import org.jetbrains.exposed.sql.SqlExpressionBuilder.eq
import org.jetbrains.exposed.sql.SqlExpressionBuilder.like
import org.jetbrains.exposed.sql.and
import org.jetbrains.exposed.sql.leftJoin
import org.jetbrains.exposed.sql.lowerCase
import org.jetbrains.exposed.sql.or
import org.jetbrains.exposed.sql.selectAll
import org.jetbrains.exposed.sql.transactions.experimental.newSuspendedTransaction
import java.util.UUID

/**
 * Handles user search queries for the GET /api/users/search endpoint.
 *
 * Search behaviour:
 * - Always matches against [Users.username] and [Users.displayName]
 *   (case-insensitive substring search).
 * - Also matches against [Users.email] when the target user has opted in via
 *   [UserSettings.searchableByEmail] = true.
 * - The authenticated caller is always excluded from the results.
 * - Each result is annotated with the friendship status between the caller
 *   and the matched user (friend / pending / none).
 * - Results are capped at [MAX_RESULTS] entries.
 */
open class UserSearchService {

    /**
     * Searches for users whose username, display_name, or (if opted in) email
     * contains [query] (case-insensitive).
     *
     * @param query    Search term (min [MIN_QUERY_LENGTH] chars).
     * @param callerId UUID of the authenticated caller (excluded from results).
     */
    open suspend fun search(query: String, callerId: UUID): UserSearchResponse {
        require(query.length >= MIN_QUERY_LENGTH) {
            "Search query must be at least $MIN_QUERY_LENGTH characters long"
        }

        val pattern = "%${query.lowercase()}%"

        return newSuspendedTransaction {

            // ------------------------------------------------------------------
            // 1. Load all friendship rows involving the caller for annotation.
            // ------------------------------------------------------------------
            val friendshipRows = Friendships.selectAll()
                .where {
                    (Friendships.requesterId eq callerId) or
                        (Friendships.receiverId eq callerId)
                }
                .toList()

            val friendshipByPeer: Map<UUID, FriendshipStatus> = friendshipRows.associate { row ->
                val peerId = if (row[Friendships.requesterId] == callerId)
                    row[Friendships.receiverId] else row[Friendships.requesterId]
                peerId to row[Friendships.status]
            }

            // ------------------------------------------------------------------
            // 2. Query users.
            //    LEFT JOIN user_settings so we can check searchable_by_email.
            //    A user matches if:
            //      a) username ILIKE pattern, OR
            //      b) display_name ILIKE pattern, OR
            //      c) email ILIKE pattern AND searchable_by_email = true
            // ------------------------------------------------------------------
            val userRows = Users
                .leftJoin(UserSettings, { Users.id }, { UserSettings.userId })
                .selectAll()
                .where {
                    val matchesUsername    = Users.username.lowerCase() like pattern
                    val matchesDisplayName = Users.displayName.lowerCase() like pattern
                    val matchesEmail       = (Users.email.lowerCase() like pattern) and
                        (UserSettings.searchableByEmail eq true)

                    val matchesQuery: Op<Boolean> =
                        matchesUsername or matchesDisplayName or matchesEmail

                    matchesQuery and (Users.id neq callerId)
                }
                .limit(MAX_RESULTS)
                .toList()

            // ------------------------------------------------------------------
            // 3. Map to response DTOs.
            // ------------------------------------------------------------------
            // 3. Map to response DTOs, applying avatar visibility rules.
            // ------------------------------------------------------------------
            val results = userRows.map { row ->
                val userId = row[Users.id]
                val friendStatus = friendshipByPeer[userId]
                val status = when (friendStatus) {
                    FriendshipStatus.ACCEPTED -> FriendshipStatusResponse.friend
                    FriendshipStatus.PENDING  -> FriendshipStatusResponse.pending
                    else                      -> FriendshipStatusResponse.none
                }

                // Resolve avatar URL respecting visibility setting.
                val resolvedAvatar = resolveAvatarUrl(
                    row            = row,
                    viewerIsFriend = friendStatus == FriendshipStatus.ACCEPTED,
                )

                UserSearchResult(
                    id               = userId.toString(),
                    username         = row[Users.username],
                    displayName      = row[Users.displayName],
                    avatarUrl        = resolvedAvatar,
                    friendshipStatus = status,
                )
            }

            UserSearchResponse(results = results, total = results.size)
        }
    }

    companion object {
        const val MAX_RESULTS = 20
        const val MIN_QUERY_LENGTH = 2

        /**
         * Resolves the effective avatar URL for a user row, applying visibility rules.
         *
         * Priority:
         *   1. custom_avatar_url (user-uploaded) always wins over avatar_url (OAuth).
         *   2. Visibility:
         *      - 'everyone'     -> return the URL
         *      - 'friends_only' -> return URL only if [viewerIsFriend] is true
         *      - 'nobody'       -> always return null
         */
        fun resolveAvatarUrl(
            row: org.jetbrains.exposed.sql.ResultRow,
            viewerIsFriend: Boolean,
        ): String? {
            val visibility = row[Users.avatarVisibility]
            if (visibility == "nobody") return null
            if (visibility == "friends_only" && !viewerIsFriend) return null
            return row[Users.customAvatarUrl] ?: row[Users.avatarUrl]
        }
    }
}
