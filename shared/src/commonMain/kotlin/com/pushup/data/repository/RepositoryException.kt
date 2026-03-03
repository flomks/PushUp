package com.pushup.data.repository

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
