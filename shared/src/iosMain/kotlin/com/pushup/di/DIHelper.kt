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
 * let helper = DIHelper.shared
 * let startWorkout = helper.startWorkoutUseCase()
 * ```
 *
 * Requires [initKoin] to have been called before any method is invoked.
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
         * Singleton instance.
         *
         * A single [DIHelper] is sufficient because all use cases are resolved
         * lazily on each call to the factory methods above.
         */
        val shared: DIHelper = DIHelper()
    }
}
