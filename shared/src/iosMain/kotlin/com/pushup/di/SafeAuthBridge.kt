package com.pushup.di

import com.pushup.data.api.CloudSyncApi
import com.pushup.data.api.KtorApiClient
import com.pushup.data.api.dto.SetUsernameRequest
import com.pushup.data.api.dto.UpdateUserProfileRequest
import com.pushup.domain.model.AuthException
import com.pushup.domain.model.User
import com.pushup.domain.repository.UserRepository
import com.pushup.domain.usecase.auth.GetCurrentUserUseCase
import com.pushup.domain.usecase.auth.LoginWithAppleUseCase
import com.pushup.domain.usecase.auth.LoginWithEmailUseCase
import com.pushup.domain.usecase.auth.LoginWithGoogleUseCase
import com.pushup.domain.usecase.auth.LogoutUseCase
import com.pushup.domain.usecase.auth.RefreshTokenUseCase
import com.pushup.domain.usecase.auth.RegisterWithEmailUseCase
import org.koin.core.component.KoinComponent
import org.koin.core.component.get
import kotlin.coroutines.cancellation.CancellationException

/**
 * Safe auth bridge for iOS.
 *
 * All methods are suspend functions that NEVER throw exceptions.
 * They return [SafeAuthResult] which contains either a [User] or an error message.
 *
 * This prevents Kotlin exceptions from crashing the iOS app when they
 * cross the Kotlin/Swift boundary via the completionHandler bridge.
 *
 * Exported to Swift as `SafeAuthBridge.shared.safeLoginWithEmail(email:password:completionHandler:)`.
 */
object SafeAuthBridge : KoinComponent {

    suspend fun safeLoginWithEmail(email: String, password: String): SafeAuthResult =
        safeCall { get<LoginWithEmailUseCase>().invoke(email, password) }

    suspend fun safeRegisterWithEmail(email: String, password: String): SafeAuthResult =
        safeCall { get<RegisterWithEmailUseCase>().invoke(email, password) }

    suspend fun safeLoginWithApple(idToken: String): SafeAuthResult =
        safeCall { get<LoginWithAppleUseCase>().invoke(idToken) }

    suspend fun safeLoginWithGoogleOAuthCode(code: String): SafeAuthResult =
        safeCall { get<LoginWithGoogleUseCase>().invokeWithOAuthCode(code) }

    suspend fun safeLoginWithImplicitTokens(
        accessToken: String,
        refreshToken: String,
        userId: String,
        userEmail: String?,
        expiresIn: Long,
    ): SafeAuthResult = safeCall {
        get<com.pushup.domain.repository.AuthRepository>().loginWithImplicitTokens(
            accessToken = accessToken,
            refreshToken = refreshToken,
            userId = userId,
            userEmail = userEmail,
            expiresIn = expiresIn,
        )
    }

    suspend fun safeGetCurrentUser(): SafeAuthResult = try {
        val user = get<GetCurrentUserUseCase>().invoke()
        SafeAuthResult(user = user, errorMessage = null)
    } catch (_: CancellationException) {
        throw CancellationException()
    } catch (_: Exception) {
        SafeAuthResult(user = null, errorMessage = null)
    }

    suspend fun safeLogout(): SafeAuthResult = try {
        get<LogoutUseCase>().invoke(clearLocalData = true)
        SafeAuthResult(user = null, errorMessage = null)
    } catch (_: CancellationException) {
        throw CancellationException()
    } catch (_: Exception) {
        SafeAuthResult(user = null, errorMessage = null)
    }

    /**
     * Updates the display name of the currently authenticated user.
     *
     * Writes to the local SQLDelight database immediately so the name is never
     * NULL even if the app is killed before the cloud sync runs. Also attempts
     * to push the change to Supabase (public.users) right away so other devices
     * see the new name on their next sync. The cloud push is best-effort: if it
     * fails (e.g. offline), the next [SyncFromCloudUseCase] run will reconcile.
     *
     * Returns a [SafeAuthResult] with the updated [User] on success, or an error
     * message on failure. Never throws.
     */
    suspend fun safeUpdateDisplayName(displayName: String): SafeAuthResult = try {
        val trimmed = displayName.trim()
        val userRepo = get<UserRepository>()
        val user = userRepo.getCurrentUser()
            ?: return SafeAuthResult(user = null, errorMessage = "No authenticated user found.")
        val updated = user.copy(displayName = trimmed)
        // 1. Persist locally first (always succeeds even when offline).
        userRepo.updateUser(updated)
        // 2. Best-effort push to Supabase. Errors are swallowed so the local
        //    update is never rolled back due to a network failure.
        val syncApi = runCatching { get<CloudSyncApi>() }.getOrNull()
        if (syncApi != null) {
            runCatching {
                syncApi.updateUserProfile(
                    userId = user.id,
                    request = UpdateUserProfileRequest(displayName = trimmed),
                )
            }
        }
        SafeAuthResult(user = updated, errorMessage = null)
    } catch (_: CancellationException) {
        throw CancellationException()
    } catch (e: Exception) {
        SafeAuthResult(user = null, errorMessage = e.message ?: "Failed to update display name.")
    }

    /**
     * Checks whether [username] is available (not taken by another user).
     *
     * Returns a [SafeUsernameCheckResult] with [available] = true if the username
     * is free to use. Never throws.
     */
    suspend fun safeCheckUsernameAvailability(username: String): SafeUsernameCheckResult = try {
        val ktorClient = runCatching { get<KtorApiClient>() }.getOrNull()
            ?: return SafeUsernameCheckResult(available = false, errorMessage = "API client not available.")
        val response = ktorClient.checkUsernameAvailability(username)
        SafeUsernameCheckResult(available = response.available, errorMessage = null)
    } catch (_: CancellationException) {
        throw CancellationException()
    } catch (e: Exception) {
        SafeUsernameCheckResult(available = false, errorMessage = e.message ?: "Failed to check username.")
    }

    /**
     * Sets the username for the currently authenticated user.
     *
     * 1. Validates the username (3-20 chars, alphanumeric + underscores).
     * 2. Calls the Ktor backend to set the username (enforces uniqueness server-side).
     * 3. Persists the username locally in the SQLDelight database.
     *
     * Returns a [SafeAuthResult] with the updated [User] on success, or an error
     * message on failure. Never throws.
     */
    suspend fun safeSetUsername(username: String): SafeAuthResult = try {
        val trimmed = username.trim().lowercase()

        // Client-side validation (mirrors server-side rules).
        when {
            trimmed.length < 3 ->
                return SafeAuthResult(user = null, errorMessage = "Username must be at least 3 characters long.")
            trimmed.length > 20 ->
                return SafeAuthResult(user = null, errorMessage = "Username must be at most 20 characters long.")
            !Regex("^[a-z0-9_]+$").matches(trimmed) ->
                return SafeAuthResult(user = null, errorMessage = "Username may only contain lowercase letters, digits, and underscores.")
        }

        val userRepo = get<UserRepository>()
        val user = userRepo.getCurrentUser()
            ?: return SafeAuthResult(user = null, errorMessage = "No authenticated user found.")

        // Call the Ktor backend to set the username (enforces uniqueness).
        val ktorClient = runCatching { get<KtorApiClient>() }.getOrNull()
        if (ktorClient != null) {
            val setUsername = runCatching {
                ktorClient.setUsername(SetUsernameRequest(username = trimmed))
            }
            val error = setUsername.exceptionOrNull()
            if (error != null) {
                val msg = error.message ?: "Failed to set username."
                // Surface conflict errors clearly.
                val userFacingMsg = if (msg.contains("409") || msg.contains("taken", ignoreCase = true) || msg.contains("conflict", ignoreCase = true)) {
                    "This username is already taken. Please choose a different one."
                } else {
                    msg
                }
                return SafeAuthResult(user = null, errorMessage = userFacingMsg)
            }
        }

        // Persist locally.
        userRepo.updateUserUsername(userId = user.id, username = trimmed)
        val updated = user.copy(username = trimmed)
        SafeAuthResult(user = updated, errorMessage = null)
    } catch (_: CancellationException) {
        throw CancellationException()
    } catch (e: Exception) {
        SafeAuthResult(user = null, errorMessage = e.message ?: "Failed to set username.")
    }

    private suspend fun safeCall(block: suspend () -> User): SafeAuthResult = try {
        SafeAuthResult(user = block(), errorMessage = null)
    } catch (e: CancellationException) {
        throw e
    } catch (e: AuthException.InvalidCredentials) {
        SafeAuthResult(user = null, errorMessage = "Email or password is incorrect.")
    } catch (e: AuthException.EmailAlreadyInUse) {
        SafeAuthResult(user = null, errorMessage = "This email address is already in use.")
    } catch (e: AuthException.WeakPassword) {
        SafeAuthResult(user = null, errorMessage = "Password is too weak.")
    } catch (e: AuthException.InvalidEmail) {
        SafeAuthResult(user = null, errorMessage = "Please enter a valid email address.")
    } catch (e: AuthException.SessionExpired) {
        SafeAuthResult(user = null, errorMessage = "Your session has expired. Please sign in again.")
    } catch (e: AuthException.NotAuthenticated) {
        SafeAuthResult(user = null, errorMessage = "Not authenticated. Please sign in.")
    } catch (e: AuthException.NetworkError) {
        SafeAuthResult(user = null, errorMessage = "Network error. Please check your connection.")
    } catch (e: AuthException.ServerError) {
        // Surface the real Supabase error message so the cause is visible.
        // e.serverMessage contains the raw body from Supabase (e.g. "Apple provider is not enabled").
        // e.message contains the formatted message from mapAuthError.
        val detail = e.serverMessage?.takeIf { it.isNotBlank() }
            ?: e.message?.takeIf { it.isNotBlank() }
            ?: "Please try again."
        SafeAuthResult(user = null, errorMessage = "Server error (${e.statusCode}): $detail")
    } catch (e: AuthException) {
        SafeAuthResult(user = null, errorMessage = e.message ?: "Authentication failed.")
    } catch (e: Exception) {
        SafeAuthResult(user = null, errorMessage = e.message ?: "An unexpected error occurred.")
    }
}

/**
 * Result of a safe auth operation. Never null — always has either a user or an error message.
 *
 * Exported to Swift as a regular class with properties:
 *   result.user     — User? (nil on failure)
 *   result.errorMessage — String? (nil on success)
 */
data class SafeAuthResult(
    val user: User?,
    val errorMessage: String?,
)

/**
 * Result of a username availability check.
 *
 * Exported to Swift as a regular class with properties:
 *   result.available     — Bool
 *   result.errorMessage  — String? (nil on success)
 */
data class SafeUsernameCheckResult(
    val available: Boolean,
    val errorMessage: String?,
)
