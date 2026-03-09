package com.pushup.di

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
 * **Usage from Swift**
 * ```swift
 * KoinIOSKt.doInitKoin()
 * let useCase = DIHelper.shared.loginWithEmailUseCase()
 * ```
 *
 * Requires [initKoin] to have been called before any method is invoked.
 */
object DIHelper : KoinComponent {

    fun getOrCreateLocalUserUseCase(): GetOrCreateLocalUserUseCase = get()
    fun startWorkoutUseCase(): StartWorkoutUseCase = get()
    fun recordPushUpUseCase(): RecordPushUpUseCase = get()
    fun finishWorkoutUseCase(): FinishWorkoutUseCase = get()

    // Auth use cases
    fun loginWithEmailUseCase(): LoginWithEmailUseCase = get()
    fun registerWithEmailUseCase(): RegisterWithEmailUseCase = get()
    fun loginWithAppleUseCase(): LoginWithAppleUseCase = get()
    fun loginWithGoogleUseCase(): LoginWithGoogleUseCase = get()
    fun logoutUseCase(): LogoutUseCase = get()
    fun getCurrentUserUseCase(): GetCurrentUserUseCase = get()
}
