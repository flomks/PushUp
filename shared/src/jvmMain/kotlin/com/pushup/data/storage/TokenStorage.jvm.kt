package com.pushup.data.storage

import com.pushup.domain.model.AuthToken

/**
 * JVM (Desktop / Test) implementation of [TokenStorage].
 *
 * Stores the token in-memory only. This implementation is intentionally
 * non-persistent -- it is used for JVM unit tests and desktop builds where
 * platform Keychain / EncryptedSharedPreferences are not available.
 *
 * **Do not use this implementation in production mobile builds.**
 */
actual class TokenStorage {

    @Volatile
    private var stored: AuthToken? = null

    /** Stores [token] in memory. */
    actual fun save(token: AuthToken) {
        stored = token
    }

    /** Returns the in-memory token, or `null` if none has been saved. */
    actual fun load(): AuthToken? = stored

    /** Clears the in-memory token. */
    actual fun clear() {
        stored = null
    }
}
