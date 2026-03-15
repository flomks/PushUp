package com.pushup.data.repository

import com.pushup.data.api.FriendCodeApiClient
import com.pushup.domain.model.FriendCode
import com.pushup.domain.model.FriendCodePrivacy
import com.pushup.domain.model.UseFriendCodeResult
import com.pushup.domain.repository.FriendCodeRepository

/**
 * Production implementation of [FriendCodeRepository].
 *
 * Delegates all operations to [FriendCodeApiClient] which communicates with
 * the Ktor backend. All calls are already main-safe because Ktor's coroutine
 * dispatcher handles thread switching internally.
 *
 * @property apiClient The HTTP client for friend code endpoints.
 */
class FriendCodeRepositoryImpl(
    private val apiClient: FriendCodeApiClient,
) : FriendCodeRepository {

    override suspend fun getMyFriendCode(): FriendCode =
        apiClient.getMyFriendCode()

    override suspend fun updatePrivacy(privacy: FriendCodePrivacy): FriendCode =
        apiClient.updatePrivacy(privacy)

    override suspend fun resetCode(): FriendCode =
        apiClient.resetCode()

    override suspend fun useFriendCode(code: String): UseFriendCodeResult =
        apiClient.useFriendCode(code)
}
