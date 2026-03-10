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
import org.slf4j.LoggerFactory

private val logger = LoggerFactory.getLogger("com.pushup.Application")

fun main() {
    // Install a global uncaught exception handler so the JVM logs the error
    // instead of silently crashing. This is critical for diagnosing crashes
    // that happen outside of Ktor's coroutine scope (e.g. in Netty threads,
    // HikariCP background threads, or Exposed transaction callbacks).
    Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
        logger.error("FATAL: Uncaught exception on thread '${thread.name}'", throwable)
    }

    val port = System.getenv("PORT")?.toIntOrNull()?.takeIf { it in 1..65535 } ?: 8080
    val host = System.getenv("HOST") ?: "0.0.0.0"

    logger.info("Starting PushUp backend on $host:$port ...")

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
    val log = LoggerFactory.getLogger("com.pushup.Application")

    log.info("Initialising plugins ...")
    configureSerialization()
    configureMonitoring()
    configureStatusPages()
    configureCORS()

    val databaseReady = configureDatabase()
    configureAuth()
    configureRouting(databaseReady = databaseReady)

    val authMode = when {
        !System.getenv("SUPABASE_URL").isNullOrBlank() -> "ENABLED (RS256/JWKS)"
        !System.getenv("SUPABASE_JWT_SECRET").isNullOrBlank() -> "ENABLED (HS256/legacy)"
        else -> "DISABLED (set SUPABASE_URL or SUPABASE_JWT_SECRET)"
    }
    log.info("=".repeat(60))
    log.info("PushUp backend ready")
    log.info("  Database: {}", if (databaseReady) "CONNECTED" else "DISABLED (no DATABASE_URL)")
    log.info("  Auth:     {}", authMode)
    log.info("  Env:      {}", System.getenv("KTOR_ENV") ?: "development")
    log.info("=".repeat(60))
}
