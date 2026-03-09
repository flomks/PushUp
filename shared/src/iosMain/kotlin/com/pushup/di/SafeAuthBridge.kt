package com.pushup.di

import com.pushup.domain.model.AuthException
import com.pushup.domain.model.User
import com.pushup.domain.usecase.auth.GetCurrentUserUseCase
import com.pushup.domain.usecase.auth.LoginWithAppleUseCase
import com.pushup.domain.usecase.auth.LoginWithEmailUseCase
import com.pushup.domain.usecase.auth.LoginWithGoogleUseCase
import com.pushup.domain.usecase.auth.LogoutUseCase
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
        SafeAuthResult(user = null, errorMessage = "Server error (${e.statusCode}). Please try again.")
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
