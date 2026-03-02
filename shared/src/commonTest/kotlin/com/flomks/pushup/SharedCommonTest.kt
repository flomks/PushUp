package com.flomks.pushup

import kotlin.test.Test
import kotlin.test.assertTrue

class SharedCommonTest {

    @Test
    fun greetingContainsPlatformName() {
        val greeting = Greeting().greet()
        assertTrue(
            greeting.startsWith("Hello, "),
            "Greeting should start with 'Hello, ' but was: $greeting",
        )
    }
}
