package com.flomks.pushup

import kotlinx.datetime.Clock
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Entry point demonstrating the KMP shared module with
 * kotlinx-serialization and kotlinx-datetime integration.
 */
@Serializable
data class HelloResponse(
    val message: String,
    val timestamp: String,
)

object Hello {

    private val json = Json { prettyPrint = true }

    /**
     * Returns a greeting string including the current local date-time.
     */
    fun greet(name: String = "World"): String {
        val now = Clock.System.now()
            .toLocalDateTime(TimeZone.currentSystemDefault())
        return "Hello, $name! Current time: $now"
    }

    /**
     * Returns a [HelloResponse] serialized as JSON string.
     */
    fun greetAsJson(name: String = "World"): String {
        val now = Clock.System.now()
            .toLocalDateTime(TimeZone.currentSystemDefault())
        val response = HelloResponse(
            message = "Hello, $name!",
            timestamp = now.toString(),
        )
        return json.encodeToString(HelloResponse.serializer(), response)
    }

    /**
     * Deserializes a JSON string back into a [HelloResponse].
     */
    fun parseResponse(jsonString: String): HelloResponse =
        json.decodeFromString(HelloResponse.serializer(), jsonString)
}
