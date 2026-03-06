package com.pushup.data.api

import com.pushup.domain.model.AuthToken

/**
 * Abstraction over the Supabase Auth REST API.
 *
 * Decouples [com.pushup.data.repository.AuthRepositoryImpl] from the concrete
 * [SupabaseAuthClient] so that tests can inject a fake implementation without
 * needing a real HTTP client.
 *
 * The production implementation is [SupabaseAuthClient].
 * Test implementations can be simple in-memory stubs.
 */
interface AuthClient {

    /**
     * Registers a new user with [email] and [password].
     *
     * @return [AuthToken] for the newly created session.
     * @throws com.pushup.domain.model.AuthException on failure.
     */
    suspend fun signUpWithEmail(email: String, password: String): AuthToken

    /**
     * Signs in an existing user with [email] and [password].
     *
     * @return [AuthToken] for the authenticated session.
     * @throws com.pushup.domain.model.AuthException on failure.
     */
    suspend fun signInWithEmail(email: String, password: String): AuthToken

    /**
     * Signs in (or registers) a user using a social provider ID token.
     *
     * @param provider The OAuth provider name: `"apple"` or `"google"`.
     * @param idToken  The identity token issued by the provider.
     * @return [AuthToken] for the authenticated session.
     * @throws com.pushup.domain.model.AuthException on failure.
     */
    suspend fun signInWithIdToken(provider: String, idToken: String): AuthToken

    /**
     * Refreshes the access token using [refreshToken].
     *
     * @return New [AuthToken] with a fresh access token.
     * @throws com.pushup.domain.model.AuthException on failure.
     */
    suspend fun refreshToken(refreshToken: String): AuthToken
}
