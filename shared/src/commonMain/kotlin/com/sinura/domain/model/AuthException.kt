package com.sinura.domain.model

/**
 * Base class for all authentication-related exceptions thrown by the auth layer.
 *
 * All Supabase Auth errors are mapped to a subclass of [AuthException] before
 * propagating to the domain or presentation layer. This keeps the domain layer
 * free of Ktor-specific types and makes error handling predictable.
 *
 * @property message Human-readable description of the error.
 * @property cause   The underlying exception that triggered this error, if any.
 */
sealed class AuthException(message: String, cause: Throwable? = null) : Exception(message, cause) {

    /**
     * The provided credentials (email/password or social token) are invalid.
     *
     * Returned by Supabase Auth when the email/password combination is wrong,
     * or when a social ID token cannot be verified.
     */
    class InvalidCredentials(
        message: String = "Invalid credentials",
        cause: Throwable? = null,
    ) : AuthException(message, cause)

    /**
     * An account with the given email address already exists.
     *
     * Returned by Supabase Auth when attempting to register with an email
     * that is already in use.
     */
    class EmailAlreadyInUse(
        message: String = "Email address is already in use",
        cause: Throwable? = null,
    ) : AuthException(message, cause)

    /**
     * The provided email address has an invalid format.
     */
    class InvalidEmail(
        message: String = "Invalid email address",
        cause: Throwable? = null,
    ) : AuthException(message, cause)

    /**
     * The provided password does not meet the minimum requirements.
     *
     * Supabase requires passwords to be at least 6 characters by default.
     */
    class WeakPassword(
        message: String = "Password is too weak",
        cause: Throwable? = null,
    ) : AuthException(message, cause)

    /**
     * The refresh token is invalid, expired, or has been revoked.
     *
     * The user must re-authenticate from scratch.
     */
    class SessionExpired(
        message: String = "Session has expired -- please sign in again",
        cause: Throwable? = null,
    ) : AuthException(message, cause)

    /**
     * No active session exists on this device.
     *
     * Thrown when an operation requires authentication but no token is stored.
     */
    class NotAuthenticated(
        message: String = "No authenticated session found",
        cause: Throwable? = null,
    ) : AuthException(message, cause)

    /**
     * A network or connectivity error occurred during the auth request.
     *
     * This is a transient error -- the caller may retry.
     */
    class NetworkError(
        message: String = "Network error during authentication",
        cause: Throwable? = null,
    ) : AuthException(message, cause)

    /**
     * The Supabase Auth server returned an unexpected error.
     *
     * @property statusCode The HTTP status code returned by the server.
     * @property serverMessage The error body returned by the server, if available.
     */
    class ServerError(
        val statusCode: Int,
        message: String = "Auth server error ($statusCode)",
        val serverMessage: String? = null,
        cause: Throwable? = null,
    ) : AuthException(message, cause)

    /**
     * An unexpected error that does not fit any of the above categories.
     */
    class Unknown(
        message: String = "Unknown authentication error",
        cause: Throwable? = null,
    ) : AuthException(message, cause)
}
