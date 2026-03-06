package com.pushup.data.api

/**
 * Base class for all API-layer exceptions thrown by [SupabaseClient] and [KtorApiClient].
 *
 * All network and HTTP errors are mapped to a subclass of [ApiException] before
 * they propagate to the domain or presentation layer. This keeps the domain layer
 * free of Ktor-specific types and makes error handling predictable.
 *
 * @property message Human-readable description of the error.
 * @property cause   The underlying exception that triggered this error, if any.
 */
sealed class ApiException(message: String, cause: Throwable? = null) : Exception(message, cause) {

    // -------------------------------------------------------------------------
    // Network-level errors (transient -- eligible for retry)
    // -------------------------------------------------------------------------

    /**
     * The request timed out before a response was received.
     *
     * This is a transient error. The retry logic in [SupabaseClient] and
     * [KtorApiClient] will automatically retry requests that fail with this
     * exception up to the configured maximum number of attempts.
     */
    class Timeout(message: String = "Request timed out", cause: Throwable? = null) :
        ApiException(message, cause)

    /**
     * The device has no network connectivity, or the server is unreachable.
     *
     * This is a transient error and will be retried automatically.
     */
    class NetworkError(message: String = "Network error", cause: Throwable? = null) :
        ApiException(message, cause)

    /**
     * The server returned HTTP 503 Service Unavailable.
     *
     * Indicates that the server is temporarily overloaded or down for maintenance.
     * This is a transient error and will be retried automatically.
     *
     * @property retryAfterSeconds Optional hint from the server (Retry-After header)
     *   indicating how many seconds to wait before retrying.
     */
    class ServiceUnavailable(
        message: String = "Service unavailable (503)",
        val retryAfterSeconds: Int? = null,
        cause: Throwable? = null,
    ) : ApiException(message, cause)

    // -------------------------------------------------------------------------
    // Authentication / authorisation errors (non-transient)
    // -------------------------------------------------------------------------

    /**
     * The request was rejected with HTTP 401 Unauthorized.
     *
     * The JWT token is missing, expired, or invalid. The caller should
     * refresh the token and retry the request manually -- the automatic
     * retry logic does NOT retry 401 responses.
     */
    class Unauthorized(message: String = "Unauthorized (401)", cause: Throwable? = null) :
        ApiException(message, cause)

    /**
     * The request was rejected with HTTP 403 Forbidden.
     *
     * The authenticated user does not have permission to perform the
     * requested operation (e.g. accessing another user's data).
     */
    class Forbidden(message: String = "Forbidden (403)", cause: Throwable? = null) :
        ApiException(message, cause)

    // -------------------------------------------------------------------------
    // Resource errors (non-transient)
    // -------------------------------------------------------------------------

    /**
     * The requested resource was not found (HTTP 404).
     *
     * @property resourceType Optional description of the resource type (e.g. "WorkoutSession").
     * @property resourceId   Optional identifier of the missing resource.
     */
    class NotFound(
        message: String = "Not found (404)",
        val resourceType: String? = null,
        val resourceId: String? = null,
        cause: Throwable? = null,
    ) : ApiException(message, cause)

    /**
     * The request payload was rejected by the server (HTTP 400 or 422).
     *
     * Indicates a programming error -- the client sent a malformed or
     * semantically invalid request body.
     *
     * @property serverMessage The error message returned by the server, if available.
     */
    class BadRequest(
        message: String = "Bad request (400)",
        val serverMessage: String? = null,
        cause: Throwable? = null,
    ) : ApiException(message, cause)

    /**
     * A conflict occurred (HTTP 409).
     *
     * For example, attempting to create a resource that already exists
     * (e.g. duplicate workout session ID).
     */
    class Conflict(message: String = "Conflict (409)", cause: Throwable? = null) :
        ApiException(message, cause)

    // -------------------------------------------------------------------------
    // Server errors (non-transient unless wrapped in ServiceUnavailable)
    // -------------------------------------------------------------------------

    /**
     * The server returned an unexpected HTTP 5xx error (other than 503).
     *
     * @property statusCode The actual HTTP status code returned by the server.
     * @property serverMessage The error body returned by the server, if available.
     */
    class ServerError(
        val statusCode: Int,
        message: String = "Server error ($statusCode)",
        val serverMessage: String? = null,
        cause: Throwable? = null,
    ) : ApiException(message, cause)

    // -------------------------------------------------------------------------
    // Serialisation / parsing errors (non-transient)
    // -------------------------------------------------------------------------

    /**
     * The response body could not be deserialised into the expected type.
     *
     * This typically indicates a breaking API change or a mismatch between
     * the client DTOs and the server response schema.
     */
    class ParseError(message: String = "Failed to parse response", cause: Throwable? = null) :
        ApiException(message, cause)

    // -------------------------------------------------------------------------
    // Catch-all
    // -------------------------------------------------------------------------

    /**
     * An unexpected error that does not fit any of the above categories.
     *
     * Wraps any [Throwable] that was not anticipated by the error-mapping logic.
     */
    class Unknown(message: String = "Unknown API error", cause: Throwable? = null) :
        ApiException(message, cause)
}

// ---------------------------------------------------------------------------
// Extension helpers
// ---------------------------------------------------------------------------

/**
 * Returns `true` if this exception represents a transient failure that is
 * safe to retry (network errors, timeouts, and 503 responses).
 */
val ApiException.isTransient: Boolean
    get() = this is ApiException.Timeout ||
        this is ApiException.NetworkError ||
        this is ApiException.ServiceUnavailable
