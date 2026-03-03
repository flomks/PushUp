package com.pushup.di

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestDispatcher
import kotlinx.datetime.Clock
import org.koin.core.context.startKoin
import org.koin.core.context.stopKoin
import org.koin.core.module.Module
import org.koin.core.qualifier.named
import org.koin.dsl.module

/**
 * Utility for setting up and tearing down a Koin context in JVM unit tests.
 *
 * This helper lives in `jvmTest` because `koin-test` depends on `kotlin-reflect`
 * and is not available on Kotlin/Native (iOS) targets.
 *
 * Usage -- call [startTestKoin] / [stopTestKoin] in your `@BeforeTest` /
 * `@AfterTest` hooks:
 *
 * ```kotlin
 * class MyUseCaseTest {
 *
 *     private val testDispatcher = StandardTestDispatcher()
 *
 *     @BeforeTest
 *     fun setUp() {
 *         startTestKoin(testDispatcher,
 *             module {
 *                 single<MyRepository> { FakeMyRepository() }
 *             }
 *         )
 *     }
 *
 *     @AfterTest
 *     fun tearDown() = stopTestKoin()
 * }
 * ```
 *
 * The [overrideModules] are loaded after [sharedModules] with `allowOverride`
 * enabled on the Koin application, so any binding declared there replaces the
 * production binding for the same type. This allows individual tests to swap
 * out specific dependencies (e.g. replace a real repository with a fake)
 * without touching the rest of the production wiring.
 *
 * A [TestDispatcher] is automatically bound under the [DB_DISPATCHER] qualifier
 * so that all repositories use the controllable test dispatcher instead of
 * [kotlinx.coroutines.Dispatchers.Default].
 */
fun startTestKoin(
    testDispatcher: TestDispatcher = StandardTestDispatcher(),
    vararg overrideModules: Module,
) {
    startKoin {
        // Allow test fakes to replace production bindings without throwing
        allowOverride(true)
        // Load shared production modules first
        modules(sharedModules)
        // Override the DB dispatcher with the controllable test dispatcher
        modules(
            module {
                single<CoroutineDispatcher>(named(DB_DISPATCHER)) { testDispatcher }
            },
        )
        // Load caller-supplied overrides last so they win over all previous bindings
        modules(overrideModules.toList())
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

/**
 * Convenience overload that also binds a fixed [Clock] for deterministic timestamps.
 *
 * @param testDispatcher The [TestDispatcher] to use for all repository coroutines.
 * @param clock A fixed or controllable [Clock] instance.
 * @param overrideModules Additional modules whose bindings override production ones.
 */
fun startTestKoin(
    testDispatcher: TestDispatcher = StandardTestDispatcher(),
    clock: Clock,
    vararg overrideModules: Module,
) {
    startTestKoin(
        testDispatcher,
        *overrideModules,
        module { single<Clock> { clock } },
    )
}
