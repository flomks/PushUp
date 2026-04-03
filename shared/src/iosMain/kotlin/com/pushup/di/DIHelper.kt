package com.pushup.di

import com.pushup.data.storage.TokenStorage
import com.pushup.domain.model.AuthToken
import com.pushup.domain.model.User
import com.pushup.domain.usecase.FinishJoggingUseCase
import com.pushup.domain.usecase.FinishWorkoutUseCase
import com.pushup.domain.usecase.GetOrCreateLocalUserUseCase
import com.pushup.domain.usecase.LiveJoggingSessionManager
import com.pushup.domain.usecase.SaveJoggingPlaybackEntriesUseCase
import com.pushup.domain.usecase.SaveJoggingSegmentsUseCase
import com.pushup.domain.usecase.RecordPushUpUseCase
import com.pushup.domain.usecase.RecordRoutePointUseCase
import com.pushup.domain.usecase.StartJoggingUseCase
import com.pushup.domain.usecase.StartWorkoutUseCase
import com.pushup.domain.usecase.auth.GetCurrentUserUseCase
import com.pushup.domain.usecase.auth.LoginWithAppleUseCase
import com.pushup.domain.usecase.auth.LoginWithEmailUseCase
import com.pushup.domain.usecase.auth.LoginWithGoogleUseCase
import com.pushup.domain.usecase.auth.LogoutUseCase
import com.pushup.domain.usecase.auth.RegisterWithEmailUseCase
import kotlinx.datetime.Clock
import org.koin.core.component.KoinComponent
import org.koin.core.component.get

/**
 * iOS-facing helper that resolves KMP use cases from the Koin DI graph.
 *
 * Declared as a Kotlin `object` so Kotlin/Native exports it to Swift as
 * `DIHelper.shared` — the standard singleton accessor pattern on iOS.
 *
 * Requires [initKoin] to have been called before any method is invoked.
 */
object DIHelper : KoinComponent {

    // Workout use cases (push-ups)
    fun getOrCreateLocalUserUseCase(): GetOrCreateLocalUserUseCase = get()
    fun startWorkoutUseCase(): StartWorkoutUseCase = get()
    fun recordPushUpUseCase(): RecordPushUpUseCase = get()
    fun finishWorkoutUseCase(): FinishWorkoutUseCase = get()

    // Jogging use cases
    fun startJoggingUseCase(): StartJoggingUseCase = get()
    fun recordRoutePointUseCase(): RecordRoutePointUseCase = get()
    fun finishJoggingUseCase(): FinishJoggingUseCase = get()
    fun saveJoggingSegmentsUseCase(): SaveJoggingSegmentsUseCase = get()
    fun saveJoggingPlaybackEntriesUseCase(): SaveJoggingPlaybackEntriesUseCase = get()
    fun liveJoggingSessionManager(): LiveJoggingSessionManager = get()

    // Auth use case accessors — used by AuthService.swift via completionHandler bridge
    fun loginWithEmailUseCase(): LoginWithEmailUseCase = get()
    fun registerWithEmailUseCase(): RegisterWithEmailUseCase = get()
    fun loginWithAppleUseCase(): LoginWithAppleUseCase = get()
    fun loginWithGoogleUseCase(): LoginWithGoogleUseCase = get()
    fun logoutUseCase(): LogoutUseCase = get()
    fun getCurrentUserUseCase(): GetCurrentUserUseCase = get()

    /**
     * Stores a Supabase Implicit OAuth session synchronously.
     *
     * Called from Swift after parsing the access_token and refresh_token
     * from the OAuth redirect URL fragment. This is a regular (non-suspend)
     * function so it is directly callable from Swift without a bridge.
     *
     * TokenStorage.save() is synchronous. The user DB upsert is fire-and-forget
     * on a background coroutine.
     *
     * @return The stored [AuthToken], or null if storage failed.
     */
    /**
     * Stores a Supabase Implicit OAuth session token in the Keychain.
     *
     * This is a regular (non-suspend) function — directly callable from Swift.
     * Only stores the token; the user DB record is created lazily when
     * getCurrentUserUseCase is called after login.
     *
     * @return Empty string on success, or an error message on failure.
     *         Using String instead of Boolean because Kotlin Boolean is
     *         exported as KotlinBoolean in Swift which causes type issues.
     */
    /**
     * Returns the current access token from the Keychain, or null if not authenticated.
     *
     * Used by PushNotificationService.swift to attach a JWT to the device-token
     * registration request without going through the full SafeAuthBridge bridge.
     */
    fun getAccessToken(): String? {
        return try {
            get<TokenStorage>().load()?.accessToken
        } catch (_: Exception) {
            null
        }
    }

    fun storeImplicitSession(
        accessToken: String,
        refreshToken: String,
        userId: String,
        userEmail: String?,
        expiresIn: Long,
    ): String {
        return try {
            val safeRefreshToken = refreshToken.ifBlank { "implicit_no_refresh" }
            val safeUserId = userId.ifBlank { "unknown" }
            val now = Clock.System.now()
            val token = AuthToken(
                accessToken = accessToken,
                refreshToken = safeRefreshToken,
                userId = safeUserId,
                userEmail = userEmail,
                expiresAt = now.epochSeconds + expiresIn,
            )
            get<TokenStorage>().save(token)
            "" // empty = success
        } catch (e: Exception) {
            e.message ?: "Unknown error storing session"
        }
    }
}
