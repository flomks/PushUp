package com.pushup.di

import com.pushup.domain.model.AuthException
import com.pushup.domain.model.User
import com.pushup.domain.repository.AuthRepository
import com.pushup.domain.usecase.FinishWorkoutUseCase
import com.pushup.domain.usecase.GetOrCreateLocalUserUseCase
import com.pushup.domain.usecase.RecordPushUpUseCase
import com.pushup.domain.usecase.StartWorkoutUseCase
import com.pushup.domain.usecase.auth.GetCurrentUserUseCase
import com.pushup.domain.usecase.auth.LoginWithAppleUseCase
import com.pushup.domain.usecase.auth.LoginWithEmailUseCase
import com.pushup.domain.usecase.auth.LoginWithGoogleUseCase
import com.pushup.domain.usecase.auth.LogoutUseCase
import com.pushup.domain.usecase.auth.RegisterWithEmailUseCase
import org.koin.core.component.KoinComponent
import org.koin.core.component.get

/**
 * iOS-facing helper that resolves KMP use cases from the Koin DI graph.
 *
 * Declared as a Kotlin `object` so Kotlin/Native exports it to Swift as
 * `DIHelper.shared` — the standard singleton accessor pattern on iOS.
 *
 * All auth methods are "safe" — they never throw exceptions across the
 * Kotlin/Swift boundary. Instead they return [AuthResult] which contains
 * either the [User] or an error message string.
 *
 * Requires [initKoin] to have been called before any method is invoked.
 */
object DIHelper : KoinComponent {

    // Workout use cases (unchanged)
    fun getOrCreateLocalUserUseCase(): GetOrCreateLocalUserUseCase = get()
    fun startWorkoutUseCase(): StartWorkoutUseCase = get()
    fun recordPushUpUseCase(): RecordPushUpUseCase = get()
    fun finishWorkoutUseCase(): FinishWorkoutUseCase = get()

    // Raw use case accessors (kept for non-auth usage)
    fun loginWithEmailUseCase(): LoginWithEmailUseCase = get()
    fun registerWithEmailUseCase(): RegisterWithEmailUseCase = get()
    fun loginWithAppleUseCase(): LoginWithAppleUseCase = get()
    fun loginWithGoogleUseCase(): LoginWithGoogleUseCase = get()
    fun logoutUseCase(): LogoutUseCase = get()
    fun getCurrentUserUseCase(): GetCurrentUserUseCase = get()

    // =========================================================================
    // Safe auth methods — NEVER throw, always return AuthResult
    // =========================================================================

    /**
     * Signs in with email and password. Never throws.
     */
    suspend fun safeLoginWithEmail(email: String, password: String): AuthResult =
        safeAuthCall { get<LoginWithEmailUseCase>().invoke(email, password) }

    /**
     * Registers with email and password. Never throws.
     */
    suspend fun safeRegisterWithEmail(email: String, password: String): AuthResult =
        safeAuthCall { get<RegisterWithEmailUseCase>().invoke(email, password) }

    /**
     * Signs in with Apple ID token. Never throws.
     */
    suspend fun safeLoginWithApple(idToken: String): AuthResult =
        safeAuthCall { get<LoginWithAppleUseCase>().invoke(idToken) }

    /**
     * Exchanges a PKCE OAuth code. Never throws.
     */
    suspend fun safeLoginWithGoogleOAuthCode(code: String): AuthResult =
        safeAuthCall { get<LoginWithGoogleUseCase>().invokeWithOAuthCode(code) }

    /**
     * Stores tokens from the Implicit OAuth flow. Never throws.
     */
    suspend fun safeLoginWithImplicitTokens(
        accessToken: String,
        refreshToken: String,
        userId: String,
        userEmail: String?,
        expiresIn: Long,
    ): AuthResult = safeAuthCall {
        get<AuthRepository>().loginWithImplicitTokens(
            accessToken = accessToken,
            refreshToken = refreshToken,
            userId = userId,
            userEmail = userEmail,
            expiresIn = expiresIn,
        )
    }

    /**
     * Gets the current user. Returns null user if not authenticated. Never throws.
     */
    suspend fun safeGetCurrentUser(): AuthResult = try {
        val user = get<GetCurrentUserUseCase>().invoke()
        AuthResult(user = user)
    } catch (_: Exception) {
        AuthResult(user = null, errorMessage = null)
    }

    /**
     * Signs out. Never throws.
     */
    suspend fun safeLogout() {
        try {
            get<LogoutUseCase>().invoke(clearLocalData = true)
        } catch (_: Exception) {
            // Best-effort logout — ignore errors
        }
    }

    // =========================================================================
    // Private
    // =========================================================================

    /**
     * Wraps any auth call so exceptions NEVER cross the Kotlin/Swift boundary.
     * Maps known AuthException subclasses to user-friendly messages.
     */
    private suspend fun safeAuthCall(block: suspend () -> User): AuthResult = try {
        AuthResult(user = block())
    } catch (e: AuthException.InvalidCredentials) {
        AuthResult(errorMessage = "Email or password is incorrect.")
    } catch (e: AuthException.EmailAlreadyInUse) {
        AuthResult(errorMessage = "This email address is already in use.")
    } catch (e: AuthException.WeakPassword) {
        AuthResult(errorMessage = "Password is too weak. Please choose a stronger password.")
    } catch (e: AuthException.InvalidEmail) {
        AuthResult(errorMessage = "Please enter a valid email address.")
    } catch (e: AuthException.SessionExpired) {
        AuthResult(errorMessage = "Your session has expired. Please sign in again.")
    } catch (e: AuthException.NotAuthenticated) {
        AuthResult(errorMessage = "Not authenticated. Please sign in.")
    } catch (e: AuthException.NetworkError) {
        AuthResult(errorMessage = "Network error: ${e.message ?: "Connection failed"}. Please check your internet connection.")
    } catch (e: AuthException.ServerError) {
        AuthResult(errorMessage = "Server error (${e.statusCode}). Please try again later.")
    } catch (e: AuthException.Unknown) {
        AuthResult(errorMessage = e.message ?: "An unknown error occurred.")
    } catch (e: AuthException) {
        AuthResult(errorMessage = e.message ?: "Authentication failed.")
    } catch (e: Exception) {
        AuthResult(errorMessage = e.message ?: "An unexpected error occurred.")
    }
}
