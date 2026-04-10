plugins {
    alias(libs.plugins.kotlinJvm)
    alias(libs.plugins.kotlinSerialization)
    alias(libs.plugins.ktor)
    application
}

group = "com.sinura"
version = "0.1.0"

application {
    mainClass.set("com.sinura.ApplicationKt")

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

    // Ktor Client core (used transitively; APNs now uses java.net.http.HttpClient directly)
    implementation(libs.ktor.client.core)
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

    // Auth0 JWKS provider -- for RS256 JWT verification via Supabase JWKS endpoint.
    // Already a transitive dependency of ktor-server-auth-jwt; declared explicitly
    // so the import is stable and the version is pinned in libs.versions.toml.
    implementation(libs.auth0.jwks.rsa)

    // Logging
    implementation(libs.logback.classic)

    // Testing
    testImplementation(libs.ktor.server.tests)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlin.testJunit)
}
