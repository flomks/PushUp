package com.sinura.service

// APNs provider service -- token-based auth (JWT/ES256), HTTP/2 via java.net.http.HttpClient.
// We use the JDK built-in HTTP client instead of Ktor CIO because Ktor CIO has a known
// bug with APNs: it falls back to HTTP/1.1 or fails to read the response body correctly,
// causing EOFException("Unexpected end of stream after reading 165 characters").
// java.net.http.HttpClient (Java 11+) negotiates HTTP/2 via ALPN natively and is stable.
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.security.KeyFactory
import java.security.interfaces.ECPrivateKey
import java.security.spec.PKCS8EncodedKeySpec
import java.time.Duration
import java.time.Instant
import java.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Sends Apple Push Notification service (APNs) pushes via the HTTP/2 provider API.
 *
 * Authentication uses APNs token-based auth (JWT) -- no certificate required.
 * The JWT is signed with an EC private key (.p8 file) and cached for up to
 * 55 minutes (Apple allows up to 60 minutes before requiring a new token).
 *
 * ## Required environment variables
 *
 *   APNS_KEY_ID        -- 10-character key ID from Apple Developer portal
 *   APNS_TEAM_ID       -- 10-character Team ID from Apple Developer portal
 *   APNS_PRIVATE_KEY   -- Contents of the .p8 file (PEM, newlines as \n)
 *   APNS_BUNDLE_ID     -- App bundle ID, e.g. "com.flomks.sinura"
 *   APNS_PRODUCTION    -- "true" for production APNs, anything else = sandbox
 *
 * If any required variable is missing, [sendPush] is a no-op and logs a warning.
 */
object ApnsService {

    private val logger = LoggerFactory.getLogger(ApnsService::class.java)

    // -------------------------------------------------------------------------
    // Configuration (read once from env at class load time)
    // -------------------------------------------------------------------------

    private val keyId      = System.getenv("APNS_KEY_ID")
    private val teamId     = System.getenv("APNS_TEAM_ID")
    private val privateKey = System.getenv("APNS_PRIVATE_KEY")
    private val bundleId   = System.getenv("APNS_BUNDLE_ID")
    private val production = System.getenv("APNS_PRODUCTION")?.lowercase() == "true"

    private val isConfigured: Boolean
        get() = !keyId.isNullOrBlank()
             && !teamId.isNullOrBlank()
             && !privateKey.isNullOrBlank()
             && !bundleId.isNullOrBlank()

    private val apnsHost: String
        get() = if (production) "api.push.apple.com" else "api.sandbox.push.apple.com"

    // -------------------------------------------------------------------------
    // JWT token cache (valid for 55 minutes)
    // -------------------------------------------------------------------------

    @Volatile private var cachedToken: String? = null
    @Volatile private var tokenIssuedAt: Long = 0L
    private const val TOKEN_TTL_SECONDS = 55 * 60L

    // -------------------------------------------------------------------------
    // HTTP/2 client (java.net.http.HttpClient -- JDK 11+)
    //
    // A single shared client is fine here: java.net.http.HttpClient is
    // thread-safe and manages its own connection pool. HTTP/2 multiplexing
    // means multiple pushes can share one connection without the EOFException
    // that plagued the Ktor CIO engine.
    // -------------------------------------------------------------------------

    private val httpClient: HttpClient = HttpClient.newBuilder()
        .version(HttpClient.Version.HTTP_2)
        .connectTimeout(Duration.ofSeconds(5))
        .build()

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * Sends a push notification to a single APNs device token.
     *
     * This is a fire-and-forget call: failures are logged but never thrown.
     * The caller does not need to handle errors.
     *
     * @param deviceToken  The hex APNs device token string.
     * @param title        Notification title (shown in bold on the lock screen).
     * @param body         Notification body text.
     * @param category     Optional APNs category for action buttons.
     * @param data         Optional key-value pairs added to the `data` field.
     */
    suspend fun sendPush(
        deviceToken: String,
        title: String,
        body: String,
        category: String? = null,
        data: Map<String, String> = emptyMap(),
    ) {
        if (!isConfigured) {
            logger.warn(
                "APNs not configured (missing APNS_KEY_ID / APNS_TEAM_ID / " +
                "APNS_PRIVATE_KEY / APNS_BUNDLE_ID). Push skipped."
            )
            return
        }

        val token = try {
            getOrRefreshToken()
        } catch (e: Exception) {
            logger.error("Failed to generate APNs JWT: ${e.message}", e)
            return
        }

        val payload = buildPayload(title, body, category, data)
        val url = "https://$apnsHost/3/device/$deviceToken"

        try {
            val request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .version(HttpClient.Version.HTTP_2)
                .timeout(Duration.ofSeconds(10))
                .header("authorization", "bearer $token")
                .header("apns-topic", bundleId!!)
                .header("apns-push-type", "alert")
                .header("apns-priority", "10")
                .header("content-type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload))
                .build()

            // sendAsync on IO dispatcher to avoid blocking a coroutine thread
            val response = withContext(Dispatchers.IO) {
                httpClient.send(request, HttpResponse.BodyHandlers.ofString())
            }

            if (response.statusCode() == 200) {
                logger.info("APNs push delivered to token=${deviceToken.take(8)}...")
            } else {
                logger.warn(
                    "APNs push failed: status=${response.statusCode()} " +
                    "token=${deviceToken.take(8)}... body=${response.body()}"
                )
            }
        } catch (e: Exception) {
            logger.error(
                "APNs HTTP request failed for token=${deviceToken.take(8)}...: ${e.message}", e
            )
        }
    }

    /**
     * Sends a push to multiple device tokens concurrently.
     * Failures for individual tokens do not affect the others.
     */
    suspend fun sendPushToAll(
        deviceTokens: List<String>,
        title: String,
        body: String,
        category: String? = null,
        data: Map<String, String> = emptyMap(),
    ) {
        deviceTokens.forEach { token ->
            sendPush(token, title, body, category, data)
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /**
     * Returns a cached JWT or generates a new one if the cached token has
     * expired (older than [TOKEN_TTL_SECONDS]).
     */
    @Synchronized
    private fun getOrRefreshToken(): String {
        val now = Instant.now().epochSecond
        val cached = cachedToken
        if (cached != null && (now - tokenIssuedAt) < TOKEN_TTL_SECONDS) {
            return cached
        }
        val newToken = generateJwt(now)
        cachedToken = newToken
        tokenIssuedAt = now
        return newToken
    }

    /**
     * Generates an APNs provider JWT signed with the EC private key.
     *
     * Format: base64url(header).base64url(claims).base64url(signature)
     * Algorithm: ES256 (ECDSA with P-256 and SHA-256)
     */
    private fun generateJwt(issuedAt: Long): String {
        val header = base64url("""{"alg":"ES256","kid":"$keyId"}""".toByteArray())
        val claims = base64url("""{"iss":"$teamId","iat":$issuedAt}""".toByteArray())
        val signingInput = "$header.$claims"

        val privateKeyPem = privateKey!!
            .replace("-----BEGIN PRIVATE KEY-----", "")
            .replace("-----END PRIVATE KEY-----", "")
            .replace("\\n", "\n")
            .replace("\n", "")
            .trim()

        val keyBytes = Base64.getDecoder().decode(privateKeyPem)
        val keySpec = PKCS8EncodedKeySpec(keyBytes)
        val keyFactory = KeyFactory.getInstance("EC")
        val ecPrivateKey = keyFactory.generatePrivate(keySpec) as ECPrivateKey

        val sig = java.security.Signature.getInstance("SHA256withECDSA").apply {
            initSign(ecPrivateKey)
            update(signingInput.toByteArray(Charsets.US_ASCII))
        }.sign()

        // APNs requires the signature in raw R||S format (64 bytes), not DER.
        val rawSig = derToRaw(sig)
        return "$signingInput.${base64url(rawSig)}"
    }

    /**
     * Converts a DER-encoded ECDSA signature to the raw R||S format
     * required by APNs (two 32-byte big-endian integers concatenated).
     */
    private fun derToRaw(der: ByteArray): ByteArray {
        // DER structure: 0x30 <len> 0x02 <rLen> <r> 0x02 <sLen> <s>
        var offset = 2 // skip 0x30 and total length
        val rLen = der[offset + 1].toInt() and 0xFF
        val r = der.copyOfRange(offset + 2, offset + 2 + rLen)
        offset += 2 + rLen
        val sLen = der[offset + 1].toInt() and 0xFF
        val s = der.copyOfRange(offset + 2, offset + 2 + sLen)

        // Pad or trim to exactly 32 bytes each
        fun normalize(bytes: ByteArray): ByteArray {
            return when {
                bytes.size == 32 -> bytes
                bytes.size > 32  -> bytes.copyOfRange(bytes.size - 32, bytes.size)
                else             -> ByteArray(32 - bytes.size) + bytes
            }
        }
        return normalize(r) + normalize(s)
    }

    /** Base64url encoding without padding. */
    private fun base64url(bytes: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

    /** Builds the APNs JSON payload. */
    private fun buildPayload(
        title: String,
        body: String,
        category: String?,
        data: Map<String, String>,
    ): String {
        val aps = buildString {
            append("""{"alert":{"title":${Json.encodeToString(title)},"body":${Json.encodeToString(body)}}""")
            append(""","sound":"default"""")
            if (category != null) append(""","category":${Json.encodeToString(category)}""")
            append("}")
        }
        val dataFields = data.entries.joinToString(",") { (k, v) ->
            "${Json.encodeToString(k)}:${Json.encodeToString(v)}"
        }
        return if (dataFields.isEmpty()) {
            """{"aps":$aps}"""
        } else {
            """{"aps":$aps,$dataFields}"""
        }
    }
}

// ---------------------------------------------------------------------------
// Payload data classes (for serialization reference -- not used directly above)
// ---------------------------------------------------------------------------

@Serializable
private data class ApnsAlert(val title: String, val body: String)

@Serializable
private data class ApnsAps(
    val alert: ApnsAlert,
    val sound: String = "default",
    val category: String? = null,
)
