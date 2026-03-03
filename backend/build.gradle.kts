plugins {
    alias(libs.plugins.kotlinJvm)
    alias(libs.plugins.kotlinSerialization)
    alias(libs.plugins.ktor)
    application
}

group = "com.pushup"
version = "0.1.0"

application {
    mainClass.set("com.pushup.ApplicationKt")

    val isDevelopment: Boolean = project.ext.has("development")
    applicationDefaultJvmArgs = listOf("-Dio.ktor.development=$isDevelopment")
}

ktor {
    fatJar {
        archiveFileName.set("pushup-backend.jar")
    }
}

dependencies {
    // Ktor Server
    implementation(libs.ktor.server.core)
    implementation(libs.ktor.server.netty)
    implementation(libs.ktor.server.contentNegotiation)
    implementation(libs.ktor.server.cors)
    implementation(libs.ktor.server.auth)
    implementation(libs.ktor.server.auth.jwt)
    implementation(libs.ktor.server.statusPages)
    implementation(libs.ktor.server.callLogging)
    implementation(libs.ktor.server.defaultHeaders)

    // Exposed ORM (DSL mode -- no DAO module needed)
    implementation(libs.exposed.core)
    implementation(libs.exposed.jdbc)
    implementation(libs.exposed.kotlin.datetime)
    implementation(libs.exposed.java.time)

    // Database drivers & connection pool
    implementation(libs.hikari.cp)
    implementation(libs.postgresql.driver)

    // Coroutines (explicit -- used by newSuspendedTransaction)
    implementation(libs.kotlinx.coroutines.core)

    // Serialization
    implementation(libs.ktor.serialization.json)
    implementation(libs.kotlinx.serialization.json)

    // Logging
    implementation(libs.logback.classic)

    // Testing
    testImplementation(libs.ktor.server.tests)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlin.testJunit)
}
