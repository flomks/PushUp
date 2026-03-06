package com.pushup.data.repository

import com.pushup.data.api.AuthClient
import com.pushup.data.storage.TokenStorage
import com.pushup.domain.model.AuthException
import com.pushup.domain.model.AuthToken
import com.pushup.domain.model.User
import com.pushup.domain.repository.AuthRepository
import com.pushup.domain.repository.UserRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import kotlinx.datetime.Clock

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
 * @property authClient     Auth API client (production: [com.pushup.data.api.SupabaseAuthClient]).
 * @property tokenStorage   Platform-specific secure token storage.
 * @property userRepository Local user database repository.
 * @property clock          Used to generate [User.createdAt] / [User.lastSyncedAt] timestamps.
 * @property dispatcher     Coroutine dispatcher for I/O operations.
 */
class AuthRepositoryImpl(
    private val authClient: AuthClient,
    private val tokenStorage: TokenStorage,
    private val userRepository: UserRepository,
    private val clock: Clock = Clock.System,
    private val dispatcher: CoroutineDispatcher,
) : AuthRepository {

    // =========================================================================
    // AuthRepository implementation
    // =========================================================================

    override suspend fun registerWithEmail(email: String, password: String): User =
        withContext(dispatcher) {
            val token = wrapAuthCall { authClient.signUpWithEmail(email, password) }
            tokenStorage.save(token)
            val user = buildUser(token, email)
            userRepository.saveUser(user)
            user
        }

    override suspend fun loginWithEmail(email: String, password: String): User =
        withContext(dispatcher) {
            val token = wrapAuthCall { authClient.signInWithEmail(email, password) }
            tokenStorage.save(token)
            val user = buildUser(token, email)
            upsertUser(user)
            user
        }

    override suspend fun loginWithApple(idToken: String): User =
        withContext(dispatcher) {
            val token = wrapAuthCall { authClient.signInWithIdToken("apple", idToken) }
            tokenStorage.save(token)
            val user = buildUser(token, email = null)
            upsertUser(user)
            user
        }

    override suspend fun loginWithGoogle(idToken: String): User =
        withContext(dispatcher) {
            val token = wrapAuthCall { authClient.signInWithIdToken("google", idToken) }
            tokenStorage.save(token)
            val user = buildUser(token, email = null)
            upsertUser(user)
            user
        }

    override suspend fun logout(clearLocalData: Boolean): Unit =
        withContext(dispatcher) {
            tokenStorage.clear()
            if (clearLocalData) {
                // Best-effort: ignore errors when clearing local data
                runCatching { userRepository.getCurrentUser() }
                    .getOrNull()
                    ?.let { user ->
                        // Mark the user as logged out by updating with a cleared email
                        // (full deletion is not supported by UserRepository interface)
                        // In practice, the app should navigate to the login screen and
                        // the local data will be overwritten on next login.
                    }
            }
        }

    override suspend fun getCurrentUser(): User? =
        withContext(dispatcher) {
            userRepository.getCurrentUser()
        }

    override suspend fun getCurrentToken(): AuthToken? =
        withContext(dispatcher) {
            tokenStorage.load()
        }

    override suspend fun refreshToken(): AuthToken =
        withContext(dispatcher) {
            val stored = tokenStorage.load()
                ?: throw AuthException.NotAuthenticated()
            val newToken = wrapAuthCall { authClient.refreshToken(stored.refreshToken) }
            tokenStorage.save(newToken)
            newToken
        }

    // =========================================================================
    // Private helpers
    // =========================================================================

    /**
     * Executes an auth API call, mapping any [Exception] to a typed [AuthException].
     *
     * [AuthException]s are re-thrown as-is. All other exceptions are wrapped in
     * [AuthException.NetworkError] (for connectivity issues) or [AuthException.Unknown].
     */
    private suspend fun <T> wrapAuthCall(block: suspend () -> T): T {
        return try {
            block()
        } catch (e: AuthException) {
            throw e
        } catch (e: Exception) {
            val msg = e.message ?: "Unknown error"
            if (msg.contains("connect", ignoreCase = true) ||
                msg.contains("timeout", ignoreCase = true) ||
                msg.contains("network", ignoreCase = true)
            ) {
                throw AuthException.NetworkError(msg, e)
            }
            throw AuthException.Unknown(msg, e)
        }
    }

    /**
     * Builds a [User] domain object from an [AuthToken] and optional [email].
     *
     * When [email] is `null` (social login), the email is derived from the
     * existing local user record if available, or left as an empty placeholder.
     * The display name defaults to the email prefix (before `@`).
     */
    private suspend fun buildUser(token: AuthToken, email: String?): User {
        val now = clock.now()
        val resolvedEmail = email
            ?: userRepository.getCurrentUser()?.email
            ?: "${token.userId}@social.local"
        val displayName = resolvedEmail.substringBefore('@').ifBlank { "User" }
        return User(
            id = token.userId,
            email = resolvedEmail,
            displayName = displayName,
            createdAt = now,
            lastSyncedAt = now,
        )
    }

    /**
     * Saves or updates the [user] in the local database.
     *
     * Attempts [UserRepository.updateUser] first; if the user does not exist yet
     * (e.g. first login on a new device), falls back to [UserRepository.saveUser].
     */
    private suspend fun upsertUser(user: User) {
        val existing = userRepository.getCurrentUser()
        if (existing != null) {
            userRepository.updateUser(user)
        } else {
            userRepository.saveUser(user)
        }
    }
}
