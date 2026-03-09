package com.pushup.domain.repository

import com.pushup.domain.model.AuthToken
import com.pushup.domain.model.User

/**
 * Repository for all authentication operations.
 *
 * Abstracts the Supabase Auth API and local token storage behind a single
 * interface so that use-cases remain independent of the underlying
 * implementation details (Ktor HTTP client, platform Keychain/EncryptedSharedPreferences).
 *
 * All operations are **main-safe** -- dispatcher switching is handled internally.
 *
 * ## Error handling
 * All methods throw [com.pushup.domain.model.AuthException] subclasses on failure.
 * Callers should catch the specific subclass they care about and let others propagate.
 */
interface AuthRepository {

    /**
     * Registers a new user with [email] and [password] via Supabase Auth.
     *
     * On success:
     * 1. The Supabase session tokens are stored in secure local storage.
     * 2. A [User] record is persisted to the local database.
     * 3. The newly created [User] is returned.
     *
     * @param email    The user's email address.
     * @param password The user's chosen password (minimum 6 characters).
     * @return The newly registered [User].
     * @throws com.pushup.domain.model.AuthException.EmailAlreadyInUse if the email is taken.
     * @throws com.pushup.domain.model.AuthException.WeakPassword if the password is too short.
     * @throws com.pushup.domain.model.AuthException.InvalidEmail if the email format is invalid.
     */
    suspend fun registerWithEmail(email: String, password: String): User

    /**
     * Signs in an existing user with [email] and [password] via Supabase Auth.
     *
     * On success the session tokens are stored in secure local storage and the
     * [User] record is upserted in the local database.
     *
     * @param email    The user's email address.
     * @param password The user's password.
     * @return The authenticated [User].
     * @throws com.pushup.domain.model.AuthException.InvalidCredentials if the credentials are wrong.
     */
    suspend fun loginWithEmail(email: String, password: String): User

    /**
     * Signs in (or registers) a user using an Apple ID token via Supabase Auth.
     *
     * Supabase handles the Apple OAuth flow server-side. The [idToken] is the
     * `identityToken` from the Apple Sign-In credential.
     *
     * @param idToken The Apple identity token string.
     * @return The authenticated [User].
     * @throws com.pushup.domain.model.AuthException.InvalidCredentials if the token is invalid.
     */
    suspend fun loginWithApple(idToken: String): User

    /**
     * Signs in (or registers) a user using a Google ID token via Supabase Auth.
     *
     * The [idToken] is the `idToken` from the Google Sign-In credential.
     *
     * @param idToken The Google identity token string.
     * @return The authenticated [User].
     * @throws com.pushup.domain.model.AuthException.InvalidCredentials if the token is invalid.
     */
    suspend fun loginWithGoogle(idToken: String): User

    /**
     * Exchanges a Supabase OAuth PKCE authorization code for a session.
     *
     * Used after the Google OAuth redirect flow. Supabase returns a `code`
     * parameter in the redirect URL which must be exchanged for tokens.
     *
     * @param code The authorization code from the OAuth redirect URL.
     * @return The authenticated [User].
     * @throws com.pushup.domain.model.AuthException on failure.
     */
    suspend fun loginWithOAuthCode(code: String): User

    /**
     * Stores a session from the Supabase OAuth Implicit Flow.
     *
     * Used when Supabase returns tokens directly in the URL fragment
     * (`#access_token=...&refresh_token=...`) instead of a PKCE code.
     *
     * @param accessToken  The Supabase JWT access token.
     * @param refreshToken The Supabase refresh token.
     * @param userId       The user ID (from the JWT `sub` claim).
     * @param userEmail    The user's email (from the JWT `email` claim), or null.
     * @param expiresIn    Seconds until the access token expires.
     * @return The authenticated [User].
     */
    suspend fun loginWithImplicitTokens(
        accessToken: String,
        refreshToken: String,
        userId: String,
        userEmail: String?,
        expiresIn: Long,
    ): User

    /**
     * Signs out the current user.
     *
     * Clears the stored tokens from secure local storage. Optionally clears
     * local user data from the database (controlled by [clearLocalData]).
     *
     * This method does NOT call the Supabase server-side sign-out endpoint --
     * the token is simply discarded locally. This is intentional: the server
     * token will expire naturally, and a network call is not required for logout.
     *
     * @param clearLocalData When `true`, the local [User] record is also deleted.
     *   Defaults to `false` to preserve offline data.
     */
    suspend fun logout(clearLocalData: Boolean = false)

    /**
     * Returns the currently authenticated [User], or `null` if not signed in.
     *
     * Reads from the local database. Does NOT make a network call.
     */
    suspend fun getCurrentUser(): User?

    /**
     * Returns the currently stored [AuthToken], or `null` if not signed in.
     *
     * Reads from secure local storage (Keychain on iOS, EncryptedSharedPreferences on Android).
     */
    suspend fun getCurrentToken(): AuthToken?

    /**
     * Refreshes the access token using the stored refresh token.
     *
     * Calls the Supabase Auth token refresh endpoint and stores the new tokens
     * in secure local storage.
     *
     * @return The new [AuthToken] with a fresh access token.
     * @throws com.pushup.domain.model.AuthException.NotAuthenticated if no refresh token is stored.
     * @throws com.pushup.domain.model.AuthException.SessionExpired if the refresh token is invalid or expired.
     */
    suspend fun refreshToken(): AuthToken
}
