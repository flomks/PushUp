package com.pushup.domain.usecase.sync

/**
 * Base class for exceptions thrown by the sync use-cases.
 *
 * Sync exceptions are distinct from [com.pushup.data.api.ApiException] (which
 * represents raw HTTP/network errors) and from domain exceptions such as
 * [com.pushup.domain.model.AuthException]. They represent higher-level sync
 * lifecycle failures that the presentation layer can handle gracefully.
 */
sealed class SyncException(message: String, cause: Throwable? = null) :
    Exception(message, cause) {

    /**
     * Thrown when a sync operation is attempted but the device has no internet
     * connection.
     *
     * Callers should catch this exception and schedule a retry for when
     * connectivity is restored rather than showing an error to the user.
     */
    class NoNetwork(
        message: String = "No internet connection",
        cause: Throwable? = null,
    ) : SyncException(message, cause)

    /**
     * Thrown when the user is not authenticated and a sync operation requires
     * a valid JWT token.
     *
     * Callers should redirect the user to the login screen.
     */
    class NotAuthenticated(
        message: String = "User is not authenticated",
        cause: Throwable? = null,
    ) : SyncException(message, cause)

    /**
     * Thrown when a sync operation fails after all retry attempts have been
     * exhausted.
     *
     * @property partialResult Optional partial result if some items were synced
     *   before the failure occurred.
     */
    class SyncFailed(
        message: String = "Sync failed after all retries",
        val partialResult: Any? = null,
        cause: Throwable? = null,
    ) : SyncException(message, cause)
}
