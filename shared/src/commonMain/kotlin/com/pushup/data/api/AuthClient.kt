package com.pushup.data.api

import com.pushup.domain.model.AuthToken
import com.pushup.domain.model.SocialProvider

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
     * @param provider The OAuth provider (typed enum -- prevents typos).
     * @param idToken  The identity token issued by the provider.
     * @return [AuthToken] for the authenticated session.
     * @throws com.pushup.domain.model.AuthException on failure.
     */
    suspend fun signInWithIdToken(provider: SocialProvider, idToken: String): AuthToken

    /**
     * Exchanges a Supabase OAuth PKCE authorization code for a session token.
     *
     * Used after the OAuth redirect flow (e.g. Google Sign-In via browser).
     * Supabase returns a `code` parameter in the redirect URL which must be
     * exchanged for an access/refresh token pair via this endpoint.
     *
     * Calls `POST /auth/v1/token?grant_type=pkce`.
     *
     * @param code The authorization code from the OAuth redirect URL.
     * @return [AuthToken] for the authenticated session.
     * @throws com.pushup.domain.model.AuthException on failure.
     */
    suspend fun exchangeOAuthCode(code: String): AuthToken

    /**
     * Refreshes the access token using [refreshToken].
     *
     * @return New [AuthToken] with a fresh access token.
     * @throws com.pushup.domain.model.AuthException on failure.
     */
    suspend fun refreshToken(refreshToken: String): AuthToken
}
