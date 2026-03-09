package com.pushup.di

import com.pushup.data.storage.TokenStorage
import com.pushup.domain.model.AuthToken
import com.pushup.domain.model.AuthException
import com.pushup.domain.model.User
import com.pushup.domain.repository.AuthRepository
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

    // Workout use cases
    fun getOrCreateLocalUserUseCase(): GetOrCreateLocalUserUseCase = get()
    fun startWorkoutUseCase(): StartWorkoutUseCase = get()
    fun recordPushUpUseCase(): RecordPushUpUseCase = get()
    fun finishWorkoutUseCase(): FinishWorkoutUseCase = get()

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
    fun storeImplicitSession(
        accessToken: String,
        refreshToken: String,
        userId: String,
        userEmail: String?,
        expiresIn: Long,
    ): AuthToken? {
        return try {
            val now = Clock.System.now()
            val token = AuthToken(
                accessToken = accessToken,
                refreshToken = refreshToken,
                userId = userId,
                userEmail = userEmail,
                expiresAt = now.epochSeconds + expiresIn,
            )
            get<TokenStorage>().save(token)

            // Upsert user record in local DB (fire-and-forget)
            val email = userEmail?.takeIf { it.isNotBlank() }
                ?: "$userId@social.local"
            val displayName = email.substringBefore('@').ifBlank { "User" }
            val user = User(
                id = userId,
                email = email,
                displayName = displayName,
                createdAt = now,
                lastSyncedAt = now,
            )
            kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.Default) {
                runCatching { get<UserRepository>().upsertUser(user) }
            }

            token
        } catch (_: Exception) {
            null
        }
    }
}
