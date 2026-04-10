package com.flomks.sinura

import kotlinx.datetime.Clock
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Greeting response model for demonstrating kotlinx-serialization
 * and kotlinx-datetime integration in the KMP shared module.
 */
@Serializable
data class HelloResponse(
    val message: String,
    val timestamp: String,
)

/**
 * Entry point demonstrating the KMP shared module capabilities
 * with kotlinx-serialization and kotlinx-datetime.
 */
object Hello {

    val json: Json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
    }

    /**
     * Returns a greeting string including the current local date-time.
     */
    fun greet(name: String = "World"): String {
        val now = currentLocalDateTime()
        return "Hello, $name! Current time: $now"
    }

    /**
     * Returns a [HelloResponse] serialized as JSON string.
     */
    fun greetAsJson(name: String = "World"): String {
        val now = currentLocalDateTime()
        val response = HelloResponse(
            message = "Hello, $name!",
            timestamp = now.toString(),
        )
        return json.encodeToString(response)
    }

    /**
     * Deserializes a JSON string back into a [HelloResponse].
     */
    fun parseResponse(jsonString: String): HelloResponse =
        json.decodeFromString<HelloResponse>(jsonString)

    private fun currentLocalDateTime(): LocalDateTime =
        Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
}
