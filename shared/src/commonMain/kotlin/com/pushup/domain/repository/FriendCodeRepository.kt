package com.pushup.domain.repository

import com.pushup.domain.model.FriendCode
import com.pushup.domain.model.FriendCodePrivacy
import com.pushup.domain.model.UseFriendCodeResult

/**
 * Repository for friend code management.
 *
 * All implementations must be **main-safe** -- dispatcher switching is handled internally.
 */
interface FriendCodeRepository {

    /**
     * Returns the authenticated user's friend code.
     * If the user does not yet have a code, one is generated automatically
     * with privacy = [FriendCodePrivacy.REQUIRE_APPROVAL].
     *
     * Calls `GET /api/friend-code`.
     *
     * @return The user's [FriendCode].
     * @throws com.pushup.data.api.ApiException on network or server errors.
     */
    suspend fun getMyFriendCode(): FriendCode

    /**
     * Updates the privacy setting of the authenticated user's friend code.
     *
     * Calls `PATCH /api/friend-code/privacy`.
     *
     * @param privacy The desired new privacy setting.
     * @return The updated [FriendCode].
     * @throws com.pushup.data.api.ApiException on network or server errors.
     */
    suspend fun updatePrivacy(privacy: FriendCodePrivacy): FriendCode

    /**
     * Generates a new random code for the authenticated user, invalidating the
     * previous one.
     *
     * Calls `POST /api/friend-code/reset`.
     *
     * @return The updated [FriendCode] with the new code value.
     * @throws com.pushup.data.api.ApiException on network or server errors.
     */
    suspend fun resetCode(): FriendCode

    /**
     * Uses a friend code entered or scanned by the authenticated user.
     *
     * Calls `POST /api/friend-code/use`.
     *
     * @param code The friend code string.
     * @return [UseFriendCodeResult] describing the outcome.
     * @throws com.pushup.data.api.ApiException on network or server errors.
     */
    suspend fun useFriendCode(code: String): UseFriendCodeResult
}
