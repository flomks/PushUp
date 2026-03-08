package com.pushup.di

import com.pushup.domain.usecase.FinishWorkoutUseCase
import com.pushup.domain.usecase.GetOrCreateLocalUserUseCase
import com.pushup.domain.usecase.RecordPushUpUseCase
import com.pushup.domain.usecase.StartWorkoutUseCase
import org.koin.core.component.KoinComponent
import org.koin.core.component.get

/**
 * iOS-facing helper that resolves KMP use cases from the Koin DI graph.
 *
 * This class is a [KoinComponent] so it can call `get()` to retrieve
 * Koin-managed instances. It is exposed to Swift as a plain class with
 * factory methods, keeping the Swift side free of Koin imports.
 *
 * **Usage from Swift**
 * ```swift
 * // At app startup (before any use case is needed):
 * KoinIOSKt.doInitKoin()
 *
 * // Then resolve use cases on demand:
 * let helper = DIHelper.shared
 * let startWorkout = helper.startWorkoutUseCase()
 * ```
 *
 * Requires [initKoin] to have been called before [shared] is first accessed.
 * The [shared] instance is created lazily so that accessing the companion
 * object before Koin is initialised does not crash.
 */
class DIHelper private constructor() : KoinComponent {

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

    companion object {
        /**
         * Lazily-initialised singleton instance.
         *
         * Lazy initialisation ensures that the [DIHelper] constructor (and
         * therefore the first Koin `get()` call) only runs after [initKoin]
         * has been called. Accessing [shared] before [initKoin] will still
         * crash at the first `get()` call, but the companion object itself
         * is safe to reference before Koin is ready.
         *
         * A single [DIHelper] is sufficient because all use cases are resolved
         * lazily on each call to the factory methods above.
         */
        val shared: DIHelper by lazy { DIHelper() }
    }
}
