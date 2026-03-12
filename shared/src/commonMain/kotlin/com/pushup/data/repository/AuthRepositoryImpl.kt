package com.pushup.data.repository

import com.pushup.data.api.AuthClient
import com.pushup.data.storage.TokenStorage
import com.pushup.db.PushUpDatabase
import com.pushup.domain.model.AuthException
import com.pushup.domain.model.AuthToken
import com.pushup.domain.model.User
import com.pushup.domain.repository.AuthRepository
import com.pushup.domain.repository.UserRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.datetime.Clock
import kotlin.coroutines.cancellation.CancellationException

/**
 * Production implementation of [AuthRepository].
 *
 * Orchestrates three collaborators:
 * - [authClient]: makes HTTP calls to the Supabase Auth REST API.
 * - [tokenStorage]: persists the [AuthToken] to platform-specific secure storage
 *   (iOS Keychain / Android EncryptedSharedPreferences).
 * - [userRepository]: persists the [User] profile to the local SQLDelight database.
 *
 * All suspend functions are main-safe -- dispatcher switching is handled by
 * [withContext] using the injected [dispatcher].
 *
 * ## Concurrency
 * [refreshToken] is protected by [refreshMutex] to prevent the single-use
 * refresh token from being consumed by two concurrent callers simultaneously.
 * The second caller will wait for the first to complete and then read the
 * already-refreshed token from storage.
 *
 * @property authClient     Auth API client (production: [com.pushup.data.api.SupabaseAuthClient]).
 * @property tokenStorage   Platform-specific secure token storage.
 * @property userRepository Local user database repository.
 * @property database       SQLDelight database used for explicit data wipe on logout.
 * @property clock          Used to generate [User.createdAt] / [User.lastSyncedAt] timestamps.
 * @property dispatcher     Coroutine dispatcher for I/O operations.
 */
class AuthRepositoryImpl(
    private val authClient: AuthClient,
    private val tokenStorage: TokenStorage,
    private val userRepository: UserRepository,
    private val database: PushUpDatabase,
    private val clock: Clock = Clock.System,
    private val dispatcher: CoroutineDispatcher,
) : AuthRepository {

    /**
     * Serialises concurrent [refreshToken] calls so that Supabase's single-use
     * refresh tokens are never consumed by two callers simultaneously.
     */
    private val refreshMutex = Mutex()

    // =========================================================================
    // AuthRepository implementation
    // =========================================================================

    override suspend fun registerWithEmail(email: String, password: String): User =
        withContext(dispatcher) {
            val token = wrapAuthCall { authClient.signUpWithEmail(email, password) }
            tokenStorage.save(token)
            val user = makeUser(token, emailOverride = email)
            // Use upsertUser -- safe even if a partial record exists from a prior attempt
            userRepository.upsertUser(user)
            user
        }

    override suspend fun loginWithEmail(email: String, password: String): User =
        withContext(dispatcher) {
            val token = wrapAuthCall { authClient.signInWithEmail(email, password) }
            tokenStorage.save(token)
            val user = makeUser(token, emailOverride = email)
            userRepository.upsertUser(user)
            user
        }

    override suspend fun loginWithApple(idToken: String): User =
        withContext(dispatcher) {
            val token = wrapAuthCall {
                authClient.signInWithIdToken(com.pushup.domain.model.SocialProvider.APPLE, idToken)
            }
            tokenStorage.save(token)
            val user = makeUser(token, emailOverride = null)
            userRepository.upsertUser(user)
            user
        }

    override suspend fun loginWithGoogle(idToken: String): User =
        withContext(dispatcher) {
            val token = wrapAuthCall {
                authClient.signInWithIdToken(com.pushup.domain.model.SocialProvider.GOOGLE, idToken)
            }
            tokenStorage.save(token)
            val user = makeUser(token, emailOverride = null)
            userRepository.upsertUser(user)
            user
        }

    override suspend fun loginWithOAuthCode(code: String): User =
        withContext(dispatcher) {
            val token = wrapAuthCall { authClient.exchangeOAuthCode(code) }
            tokenStorage.save(token)
            val user = makeUser(token, emailOverride = null)
            userRepository.upsertUser(user)
            user
        }

    override suspend fun loginWithImplicitTokens(
        accessToken: String,
        refreshToken: String,
        userId: String,
        userEmail: String?,
        expiresIn: Long,
    ): User = withContext(dispatcher) {
        val now = clock.now()
        val token = AuthToken(
            accessToken = accessToken,
            refreshToken = refreshToken,
            userId = userId,
            userEmail = userEmail,
            expiresAt = now.epochSeconds + expiresIn,
        )
        tokenStorage.save(token)
        val user = makeUser(token, emailOverride = userEmail)
        userRepository.upsertUser(user)
        user
    }

    override suspend fun logout(clearLocalData: Boolean): Unit =
        withContext(dispatcher) {
            // Always clear the token first so no further authenticated calls can be made.
            tokenStorage.clear()

            // Wipe ALL local user data to prevent stale rows from appearing after
            // a re-login with the same account (same UUID).
            //
            // Background: SQLite foreign-key cascades only fire when
            // `PRAGMA foreign_keys = ON` is set. Even with that pragma enabled,
            // we delete child tables explicitly first to guarantee correctness on
            // all existing database instances (including those opened before the
            // pragma was added). The order matters: child rows must be deleted
            // before the parent User row to satisfy FK constraints.
            runCatching {
                val userId = userRepository.getCurrentUser()?.id ?: return@runCatching
                val queries = database.databaseQueries
                queries.transaction {
                    // Delete child rows first (FK order).
                    queries.deleteWorkoutSessionsByUserId(userId)
                    queries.deleteTimeCreditByUserId(userId)
                    queries.deleteUserSettingsByUserId(userId)
                    queries.deleteUserLevel(userId)          // deleteUserLevel uses userId column
                    // Delete the parent User row last.
                    queries.deleteUser(id = userId)
                }
            }
        }

    override suspend fun getCurrentUser(): User? =
        withContext(dispatcher) {
            // Only return a user if a valid token also exists in secure storage.
            // This prevents stale DB entries (e.g. from a previous session that
            // was not properly cleared) from being treated as authenticated.
            val token = tokenStorage.load() ?: return@withContext null
            // Token exists — return the local user record.
            userRepository.getCurrentUser()
        }

    override suspend fun getCurrentToken(): AuthToken? =
        withContext(dispatcher) {
            tokenStorage.load()
        }

    override suspend fun refreshToken(): AuthToken =
        // Serialise concurrent refresh calls: the second caller waits for the first
        // to complete, then reads the already-refreshed token from storage.
        refreshMutex.withLock {
            withContext(dispatcher) {
                val stored = tokenStorage.load()
                    ?: throw AuthException.NotAuthenticated()
                val newToken = wrapAuthCall { authClient.refreshToken(stored.refreshToken) }
                tokenStorage.save(newToken)
                newToken
            }
        }

    // =========================================================================
    // Private helpers
    // =========================================================================

    /**
     * Executes an auth API call, mapping any [Exception] to a typed [AuthException].
     *
     * [CancellationException] is always re-thrown first to preserve structured
     * concurrency. [AuthException]s are re-thrown as-is. All other exceptions are
     * wrapped in [AuthException.NetworkError] (for connectivity issues) or
     * [AuthException.Unknown].
     */
    private suspend fun <T> wrapAuthCall(block: suspend () -> T): T {
        return try {
            block()
        } catch (e: CancellationException) {
            // Never swallow cancellation.
            throw e
        } catch (e: AuthException) {
            // Already typed — re-throw as-is.
            throw e
        } catch (e: Exception) {
            val msg = e.message ?: e::class.simpleName ?: "Unknown error"
            when {
                msg.contains("connect", ignoreCase = true) ||
                msg.contains("timeout", ignoreCase = true) ||
                msg.contains("network", ignoreCase = true) ||
                msg.contains("unreachable", ignoreCase = true) ||
                msg.contains("refused", ignoreCase = true) ->
                    throw AuthException.NetworkError(msg, e)
                msg.contains("JsonDecoding", ignoreCase = true) ||
                msg.contains("SerializationException", ignoreCase = true) ->
                    throw AuthException.ServerError(0, "Unexpected server response", msg, e)
                else -> throw AuthException.Unknown(msg, e)
            }
        }
    }

    /**
     * Constructs a [User] domain object from an [AuthToken].
     *
     * Email resolution priority:
     * 1. [emailOverride] -- provided by the caller for email/password flows (always accurate).
     * 2. [AuthToken.userEmail] -- returned by the Supabase Auth server in the session response.
     *    Present for most social logins when the provider shares the email.
     * 3. A synthetic placeholder `"<userId>@social.local"` -- last resort for social logins
     *    where the provider does not share the email (e.g. Apple with "Hide My Email").
     *    The placeholder is clearly synthetic and will not be displayed to the user.
     *
     * The display name defaults to the local part of the email (before `@`).
     *
     * @param token         The auth token returned by the server.
     * @param emailOverride Caller-supplied email (non-null for email/password flows).
     */
    private fun makeUser(token: AuthToken, emailOverride: String?): User {
        val now = clock.now()
        val email = emailOverride?.trim()
            ?: token.userEmail?.takeIf { it.isNotBlank() }
            ?: "${token.userId}@social.local"
        val displayName = email.substringBefore('@').ifBlank { "User" }
        return User(
            id = token.userId,
            email = email,
            displayName = displayName,
            createdAt = now,
            lastSyncedAt = now,
        )
    }
}
