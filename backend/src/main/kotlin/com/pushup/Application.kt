package com.pushup

import com.pushup.plugins.configureAuth
import com.pushup.plugins.configureCORS
import com.pushup.plugins.configureDatabase
import com.pushup.plugins.configureMonitoring
import com.pushup.plugins.configureRouting
import com.pushup.plugins.configureSerialization
import com.pushup.plugins.configureStatusPages
import io.ktor.server.application.Application
import io.ktor.server.engine.EngineConnectorBuilder
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty

fun main() {
    val port = System.getenv("PORT")?.toIntOrNull()?.takeIf { it in 1..65535 } ?: 8080
    val host = System.getenv("HOST") ?: "0.0.0.0"

    embeddedServer(Netty, configure = {
        connectors.add(EngineConnectorBuilder().apply {
            this.host = host
            this.port = port
        })
        shutdownGracePeriod = 2000
        shutdownTimeout = 5000
    }) {
        module()
    }.start(wait = true)
}

fun Application.module() {
    configureSerialization()
    configureMonitoring()
    configureStatusPages()
    configureCORS()
    configureDatabase()
    configureAuth()
    configureRouting()
}
