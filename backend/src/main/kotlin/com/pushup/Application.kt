package com.pushup

import com.pushup.plugins.configureAuth
import com.pushup.plugins.configureCORS
import com.pushup.plugins.configureMonitoring
import com.pushup.plugins.configureRouting
import com.pushup.plugins.configureSerialization
import io.ktor.server.application.Application
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty

fun main() {
    val port = System.getenv("PORT")?.toIntOrNull() ?: 8080
    val host = System.getenv("HOST") ?: "0.0.0.0"

    embeddedServer(
        Netty,
        port = port,
        host = host,
        module = Application::module,
    ).start(wait = true)
}

fun Application.module() {
    configureSerialization()
    configureMonitoring()
    configureCORS()
    configureAuth()
    configureRouting()
}
