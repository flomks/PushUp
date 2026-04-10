package com.flomks.sinura

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
        val result = Hello.greet("Sinura")
        assertContains(result, "Hello, PushUp!")
    }

    @Test
    fun greetIncludesIso8601Timestamp() {
        val result = Hello.greet()
        // Verify ISO-8601 date-time pattern: YYYY-MM-DDTHH:MM
        assertTrue(
            result.matches(Regex(""".*\d{4}-\d{2}-\d{2}T\d{2}:\d{2}.*""")),
            "Expected ISO-8601 timestamp in: $result",
        )
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
    fun serializationRoundtripPreservesData() {
        val original = HelloResponse(
            message = "Hello, Serialization!",
            timestamp = "2026-03-02T12:00:00",
        )

        val jsonString = Hello.json.encodeToString(original)
        val restored = Hello.json.decodeFromString<HelloResponse>(jsonString)

        assertEquals(original, restored)
    }
}
