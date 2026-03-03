package com.pushup.di

import org.koin.core.context.startKoin
import org.koin.core.context.stopKoin
import org.koin.core.module.Module
import org.koin.test.KoinTest

/**
 * Utility for setting up and tearing down a Koin context in unit tests.
 *
 * Usage -- extend [KoinTest] and call [startTestKoin] / [stopTestKoin] in
 * your `@BeforeTest` / `@AfterTest` hooks:
 *
 * ```kotlin
 * class MyUseCaseTest : KoinTest {
 *
 *     @BeforeTest
 *     fun setUp() {
 *         startTestKoin(
 *             module {
 *                 single<MyRepository> { FakeMyRepository() }
 *             }
 *         )
 *     }
 *
 *     @AfterTest
 *     fun tearDown() = stopTestKoin()
 *
 *     @Test
 *     fun myTest() {
 *         val useCase: MyUseCase by inject()
 *         // ...
 *     }
 * }
 * ```
 *
 * The [overrideModules] list is loaded **after** [sharedModules], so any
 * binding declared there will override the production binding for the same
 * type. This allows individual tests to swap out specific dependencies
 * (e.g. replace a real repository with a fake) without touching the rest
 * of the production wiring.
 */
fun startTestKoin(vararg overrideModules: Module) {
    startKoin {
        // Allow overrides so test fakes can replace production bindings
        allowOverride(true)
        modules(sharedModules + overrideModules.toList())
    }
}

/**
 * Stops the Koin context started by [startTestKoin].
 *
 * Must be called in `@AfterTest` to prevent context leakage between tests.
 */
fun stopTestKoin() {
    stopKoin()
}
