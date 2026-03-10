package com.pushup.data.api

import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.header
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.http.isSuccess
import kotlinx.coroutines.delay
import kotlinx.serialization.SerializationException

/**
 * Shared base for [SupabaseClient] and [KtorApiClient].
 *
 * Provides two reusable building blocks that would otherwise be duplicated
 * across both clients:
 *
 * - [withRetry]: executes a suspending block with exponential back-off retry
 *   logic for transient [ApiException]s.
 * - [withRetryAndTokenRefresh]: like [withRetry] but also retries once on
 *   [ApiException.Unauthorized] by invoking [onRefreshToken] first. Use this
 *   in clients that have access to a token-refresh callback.
 * - [HttpResponse.expectSuccess]: maps non-2xx HTTP responses to typed
 *   [ApiException] subclasses.
 * - [HttpRequestBuilder.bearerAuth]: convenience extension to add an
 *   `Authorization: Bearer <token>` header.
 *
 * Both clients inherit from this class and call these helpers directly,
 * keeping the public API surface clean and the retry/error-mapping logic
 * in a single, testable place.
 */
abstract class ApiClientBase(
    /** Maximum number of retry attempts for transient errors. */
    protected val maxRetries: Int = 3,
) {

    // =========================================================================
    // Retry
    // =========================================================================

    /**
     * Executes [block] with automatic retry logic for transient errors.
     *
     * **Retry policy:**
     * - Retries up to [maxRetries] times on [ApiException.isTransient] errors
     *   (network errors, timeouts, 503 responses).
     * - Uses exponential back-off: `100ms * 2^attempt` (100ms, 200ms, 400ms).
     * - [SerializationException] is immediately mapped to [ApiException.ParseError]
     *   and rethrown without retrying (it is a programming error, not transient).
     * - Non-transient [ApiException]s (401, 403, 404, etc.) are rethrown immediately.
     * - Any other [Exception] is wrapped in [ApiException.NetworkError] and retried.
     *
     * @param block The suspending operation to execute.
     * @return The result of [block] on success.
     * @throws ApiException if all retry attempts fail or a non-transient error occurs.
     */
    protected suspend fun <T> withRetry(block: suspend () -> T): T {
        var lastException: ApiException? = null
        repeat(maxRetries) { attempt ->
            try {
                return block()
            } catch (e: SerializationException) {
                // Parsing failures are programming errors -- never retry.
                throw ApiException.ParseError(cause = e)
            } catch (e: ApiException) {
                if (!e.isTransient) throw e
                lastException = e
                delay(100L * (1L shl attempt)) // 100ms, 200ms, 400ms
            } catch (e: Exception) {
                // Map unknown exceptions to NetworkError and retry.
                lastException = ApiException.NetworkError(
                    message = e.message ?: "Network error",
                    cause = e,
                )
                delay(100L * (1L shl attempt))
            }
        }
        throw lastException ?: ApiException.Unknown("All retry attempts exhausted")
    }

    /**
     * Executes [block] with automatic retry for transient errors AND a single
     * reactive retry on [ApiException.Unauthorized].
     *
     * When a 401 is received, [onRefreshToken] is called to obtain a fresh token
     * (the [JwtTokenProvider] implementation will call the auth server). The
     * [block] is then retried once with the new token. If the second attempt also
     * returns 401, the exception is rethrown immediately (the session is truly
     * invalid and the user must log in again).
     *
     * This handles the race condition where a token passes the proactive expiry
     * check in [JwtTokenProvider] but expires before the server processes the
     * request (e.g. clock skew or a request that takes longer than the remaining
     * token lifetime).
     *
     * @param onRefreshToken Suspend callback that forces a token refresh and
     *   returns the new access token. Typically delegates to
     *   [com.pushup.domain.repository.AuthRepository.refreshToken].
     * @param block The suspending operation to execute. Should call [onRefreshToken]
     *   (or the token provider) internally to pick up the refreshed token.
     * @return The result of [block] on success.
     * @throws ApiException if all retry attempts fail or a non-transient error occurs.
     */
    protected suspend fun <T> withRetryAndTokenRefresh(
        onRefreshToken: suspend () -> Unit,
        block: suspend () -> T,
    ): T {
        return try {
            withRetry(block)
        } catch (e: ApiException.Unauthorized) {
            // Attempt a single token refresh and retry.
            try {
                onRefreshToken()
            } catch (_: Exception) {
                // If the refresh itself fails, surface the original 401.
                throw e
            }
            // Retry once after refresh -- do NOT wrap in withRetry again to
            // avoid masking a genuine 401 with repeated refresh attempts.
            block()
        }
    }

    // =========================================================================
    // HTTP response helpers
    // =========================================================================

    /**
     * Throws a typed [ApiException] if the HTTP response status is not 2xx.
     *
     * Maps well-known HTTP status codes to specific [ApiException] subclasses.
     * Unknown 4xx/5xx codes fall through to [ApiException.ServerError].
     */
    protected suspend fun HttpResponse.expectSuccess() {
        if (status.isSuccess()) return
        val body = runCatching { bodyAsText() }.getOrNull()
        throw when (status) {
            HttpStatusCode.Unauthorized        -> ApiException.Unauthorized(body ?: "Unauthorized (401)")
            HttpStatusCode.Forbidden           -> ApiException.Forbidden(body ?: "Forbidden (403)")
            HttpStatusCode.NotFound            -> ApiException.NotFound(body ?: "Not found (404)")
            HttpStatusCode.BadRequest          -> ApiException.BadRequest(serverMessage = body)
            HttpStatusCode.UnprocessableEntity -> ApiException.BadRequest(serverMessage = body)
            HttpStatusCode.Conflict            -> ApiException.Conflict(body ?: "Conflict (409)")
            HttpStatusCode.ServiceUnavailable  -> ApiException.ServiceUnavailable(body ?: "Service unavailable (503)")
            else                               -> ApiException.ServerError(
                statusCode = status.value,
                serverMessage = body,
            )
        }
    }

    // =========================================================================
    // Request builder helpers
    // =========================================================================

    /**
     * Adds an `Authorization: Bearer <token>` header to the request.
     */
    protected fun HttpRequestBuilder.bearerAuth(token: String) {
        header("Authorization", "Bearer $token")
    }
}
