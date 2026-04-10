package com.sinura.data.storage

import com.sinura.domain.model.AuthToken

/**
 * Platform-agnostic secure storage for [AuthToken].
 *
 * Each platform provides its own implementation backed by the most secure
 * credential store available:
 * - **iOS**: Keychain Services (`SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`)
 * - **Android**: `EncryptedSharedPreferences` (Jetpack Security)
 * - **JVM/Desktop**: In-memory storage (for tests and desktop builds)
 *
 * All operations are synchronous at the storage level but are called from
 * coroutines via the repository layer, which handles dispatcher switching.
 *
 * ## Security notes
 * - The token is serialised to JSON before storage and deserialised on read.
 * - On iOS the item is stored with `kSecAttrAccessibleAfterFirstUnlock` so it
 *   is available after the device is unlocked for the first time (required for
 *   background refresh).
 * - On Android the `EncryptedSharedPreferences` key is stored in the Android
 *   Keystore and the value is AES-256-GCM encrypted.
 */
expect class TokenStorage {

    /**
     * Persists [token] to secure storage, overwriting any previously stored token.
     *
     * @param token The [AuthToken] to store.
     */
    fun save(token: AuthToken)

    /**
     * Returns the stored [AuthToken], or `null` if no token has been saved.
     */
    fun load(): AuthToken?

    /**
     * Deletes the stored token from secure storage.
     *
     * This is a no-op if no token is currently stored.
     */
    fun clear()
}
