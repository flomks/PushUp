package com.sinura.data.api

/**
 * Provides the current JWT access token for authenticated API requests.
 *
 * Implementations are platform-specific and typically delegate to the
 * Supabase Auth session. The token is fetched lazily on every call so
 * that it is always fresh (Supabase tokens expire after 1 hour).
 *
 * ## Usage in Koin
 * Bind an implementation in your platform-specific module:
 * ```kotlin
 * single<JwtTokenProvider>(named(JWT_TOKEN_PROVIDER)) {
 *     JwtTokenProvider {
 *         supabaseAuth.currentSession?.accessToken
 *             ?: error("User is not authenticated")
 *     }
 * }
 * ```
 *
 * ## Usage in tests
 * ```kotlin
 * val fakeProvider = JwtTokenProvider { "test-jwt-token" }
 * ```
 */
fun interface JwtTokenProvider {
    /**
     * Returns the current JWT access token.
     *
     * This function is `suspend` because fetching a fresh token may require
     * a network call (e.g. refreshing an expired token via Supabase Auth).
     *
     * @throws Exception if the user is not authenticated or the token cannot
     *   be retrieved.
     */
    suspend fun getToken(): String
}
