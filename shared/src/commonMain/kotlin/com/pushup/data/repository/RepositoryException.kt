package com.pushup.data.repository

import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext

/**
 * Domain-specific exception thrown by repository implementations when a
 * database operation fails.
 *
 * Wraps the underlying platform-specific database exception so that
 * consumers only depend on this class rather than on SQLDelight or
 * JDBC/Native driver exception types.
 *
 * @param message A human-readable description of what went wrong.
 * @param cause The original exception thrown by the database layer.
 */
class RepositoryException(
    message: String,
    cause: Throwable? = null,
) : RuntimeException(message, cause)

/**
 * Executes [block] on [dispatcher], wrapping any non-cancellation exception
 * in a [RepositoryException].
 *
 * [CancellationException] is always re-thrown to preserve structured
 * concurrency. Already-wrapped [RepositoryException]s are re-thrown as-is
 * to avoid double-wrapping.
 */
internal suspend inline fun <T> safeDbCall(
    dispatcher: CoroutineDispatcher,
    message: String,
    crossinline block: suspend () -> T,
): T = withContext(dispatcher) {
    try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: RepositoryException) {
        throw e
    } catch (e: Exception) {
        throw RepositoryException(message, e)
    }
}
