package com.pushup.plugins

import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import kotlinx.serialization.json.Json

fun Application.configureSerialization() {
    val isDev = System.getenv("KTOR_ENV") != "production"

    install(ContentNegotiation) {
        json(
            Json {
                prettyPrint = isDev
                isLenient = false
                ignoreUnknownKeys = true
                encodeDefaults = true
            }
        )
    }
}
