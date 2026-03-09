package com.pushup.di

import com.pushup.data.storage.TokenStorage
import com.pushup.domain.model.AuthToken
import com.pushup.domain.model.User
import com.pushup.domain.repository.UserRepository
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock
import org.koin.core.component.KoinComponent
import org.koin.core.component.get

/**
 * iOS-facing helper that resolves KMP use cases from the Koin DI graph.
 *
 * This class is a [KoinComponent] so it can call `get()` to retrieve
 * Koin-managed instances. It is exposed to Swift as a plain class with
 * factory methods, keeping the Swift side free of Koin imports.
 *
 * Declared as a Kotlin `object` so Kotlin/Native exports it to Swift as
 * `DIHelper.shared` — the standard singleton accessor pattern on iOS.
 *
 * **Usage from Swift**
 * ```swift
 * // At app startup (before any use case is needed):
 * KoinIOSKt.doInitKoin()
 *
 * // Then resolve use cases on demand:
 * let useCase = DIHelper.shared.loginWithEmailUseCase()
 * ```
 *
 * Requires [initKoin] to have been called before any method is invoked.
 */
object DIHelper : KoinComponent {

    /**
     * Returns a new [GetOrCreateLocalUserUseCase] instance from Koin.
     *
     * Use cases are registered as `factory` in [useCaseModule], so each call
     * returns a fresh instance.
     */
    fun getOrCreateLocalUserUseCase(): GetOrCreateLocalUserUseCase = get()

    /**
     * Returns a new [StartWorkoutUseCase] instance from Koin.
     */
    fun startWorkoutUseCase(): StartWorkoutUseCase = get()

    /**
     * Returns a new [RecordPushUpUseCase] instance from Koin.
     */
    fun recordPushUpUseCase(): RecordPushUpUseCase = get()

    /**
     * Returns a new [FinishWorkoutUseCase] instance from Koin.
     */
    fun finishWorkoutUseCase(): FinishWorkoutUseCase = get()

    // =========================================================================
    // Auth use cases
    // =========================================================================

    /**
     * Returns a new [LoginWithEmailUseCase] instance from Koin.
     */
    fun loginWithEmailUseCase(): LoginWithEmailUseCase = get()

    /**
     * Returns a new [RegisterWithEmailUseCase] instance from Koin.
     */
    fun registerWithEmailUseCase(): RegisterWithEmailUseCase = get()

    /**
     * Returns a new [LoginWithAppleUseCase] instance from Koin.
     *
     * Pass the `identityToken` string from `ASAuthorizationAppleIDCredential`.
     */
    fun loginWithAppleUseCase(): LoginWithAppleUseCase = get()

    /**
     * Returns a new [LoginWithGoogleUseCase] instance from Koin.
     *
     * Pass the `idToken` string from the Google Sign-In credential.
     */
    fun loginWithGoogleUseCase(): LoginWithGoogleUseCase = get()

    /**
     * Returns a new [LogoutUseCase] instance from Koin.
     */
    fun logoutUseCase(): LogoutUseCase = get()

    /**
     * Returns a new [GetCurrentUserUseCase] instance from Koin.
     */
    fun getCurrentUserUseCase(): GetCurrentUserUseCase = get()

    // =========================================================================
    // OAuth session storage (for Supabase OAuth redirect flow)
    // =========================================================================

    /**
     * Stores a Supabase OAuth session directly in secure token storage.
     *
     * Used after the Google OAuth redirect flow, where Supabase has already
     * authenticated the user server-side and returned a complete session
     * (access_token + refresh_token) in the redirect URL fragment.
     *
     * Also upserts a [User] record in the local database so the app can
     * display the user's profile immediately without a separate API call.
     *
     * @param accessToken  The Supabase JWT access token.
     * @param refreshToken The Supabase refresh token.
     * @param userId       The Supabase user ID (from the JWT `sub` claim).
     * @param userEmail    The user's email address (from the JWT `email` claim), or null.
     * @param expiresAt    Unix epoch seconds at which the access token expires.
     */
    fun storeOAuthSession(
        accessToken: String,
        refreshToken: String,
        userId: String,
        userEmail: String?,
        expiresAt: Long,
    ) {
        val token = AuthToken(
            accessToken = accessToken,
            refreshToken = refreshToken,
            userId = userId,
            userEmail = userEmail,
            expiresAt = expiresAt,
        )
        val storage = get<TokenStorage>()
        storage.save(token)

        // Upsert a local user record so the app can display the profile
        val now = Clock.System.now()
        val email = userEmail?.takeIf { it.isNotBlank() } ?: "$userId@social.local"
        val displayName = email.substringBefore('@').ifBlank { "User" }
        val user = User(
            id = userId,
            email = email,
            displayName = displayName,
            createdAt = now,
            lastSyncedAt = now,
        )
        val userRepository = get<UserRepository>()
        // Fire-and-forget: upsert runs on the DB dispatcher inside the repository
        GlobalScope.launch(Dispatchers.Default) {
            runCatching { userRepository.upsertUser(user) }
        }
    }

}


