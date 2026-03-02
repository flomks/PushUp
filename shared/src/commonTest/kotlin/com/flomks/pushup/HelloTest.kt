package com.flomks.pushup

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class HelloTest {

    @Test
    fun greetReturnsHelloWorld() {
        val result = Hello.greet()
        assertContains(result, "Hello, World!")
    }

    @Test
    fun greetWithNameReturnsPersonalizedGreeting() {
        val result = Hello.greet("PushUp")
        assertContains(result, "Hello, PushUp!")
    }

    @Test
    fun greetIncludesTimestamp() {
        val result = Hello.greet()
        // Timestamp format contains a 'T' separator between date and time
        assertContains(result, "T")
    }

    @Test
    fun greetAsJsonReturnsValidJson() {
        val jsonString = Hello.greetAsJson("Test")
        assertContains(jsonString, "\"message\"")
        assertContains(jsonString, "\"timestamp\"")
        assertContains(jsonString, "Hello, Test!")
    }

    @Test
    fun parseResponseDeserializesCorrectly() {
        val jsonString = Hello.greetAsJson("Roundtrip")
        val response = Hello.parseResponse(jsonString)

        assertEquals("Hello, Roundtrip!", response.message)
        assertNotNull(response.timestamp)
        assertTrue(response.timestamp.isNotBlank())
    }

    @Test
    fun serializationRoundtripPreservesData() = runTest {
        val original = HelloResponse(
            message = "Hello, Coroutines!",
            timestamp = "2026-03-02T12:00:00",
        )

        val json = kotlinx.serialization.json.Json.encodeToString(
            HelloResponse.serializer(),
            original,
        )
        val restored = kotlinx.serialization.json.Json.decodeFromString(
            HelloResponse.serializer(),
            json,
        )

        assertEquals(original, restored)
    }
}
