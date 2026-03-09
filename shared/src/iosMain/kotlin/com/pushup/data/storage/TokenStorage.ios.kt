package com.pushup.data.storage

import com.pushup.domain.model.AuthToken
import kotlinx.cinterop.BetaInteropApi
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.value
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import platform.CoreFoundation.CFDictionaryCreateMutable
import platform.CoreFoundation.CFDictionarySetValue
import platform.CoreFoundation.CFMutableDictionaryRef
import platform.CoreFoundation.CFTypeRefVar
import platform.CoreFoundation.kCFAllocatorDefault
import platform.CoreFoundation.kCFBooleanTrue
import platform.CoreFoundation.kCFTypeDictionaryKeyCallBacks
import platform.CoreFoundation.kCFTypeDictionaryValueCallBacks
import platform.Foundation.CFBridgingRelease
import platform.Foundation.CFBridgingRetain
import platform.Foundation.NSData
import platform.Foundation.NSString
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.create
import platform.Foundation.dataUsingEncoding
import platform.Security.SecItemAdd
import platform.Security.SecItemCopyMatching
import platform.Security.SecItemDelete
import platform.Security.SecItemUpdate
import platform.Security.errSecDuplicateItem
import platform.Security.errSecItemNotFound
import platform.Security.errSecSuccess
import platform.Security.kSecAttrAccessible
import platform.Security.kSecAttrAccessibleAfterFirstUnlock
import platform.Security.kSecAttrAccount
import platform.Security.kSecAttrService
import platform.Security.kSecClass
import platform.Security.kSecClassGenericPassword
import platform.Security.kSecMatchLimit
import platform.Security.kSecMatchLimitOne
import platform.Security.kSecReturnData
import platform.Security.kSecValueData

/**
 * iOS implementation of [TokenStorage] backed by the iOS Keychain.
 *
 * The [AuthToken] is serialised to JSON, encoded as UTF-8 bytes, and stored
 * as a generic password item in the Keychain under [SERVICE] / [ACCOUNT].
 *
 * The item is stored with `kSecAttrAccessibleAfterFirstUnlock` so that it is
 * available after the device is unlocked for the first time -- this is required
 * for background token refresh operations.
 *
 * ## Kotlin/Native 2.3 compatibility
 * Keychain Security constants (kSecClass, kSecAttrService, etc.) are typed as
 * `CPointer<__CFString>?` in the cinterop bindings. They cannot be used as keys
 * in `NSMutableDictionary` (which requires `NSCopyingProtocol`).
 *
 * The correct approach is to build query dictionaries using the CoreFoundation
 * `CFDictionaryCreateMutable` / `CFDictionarySetValue` API, which accepts
 * `COpaquePointer` values directly. All values (including Kotlin Strings and
 * NSData) are bridged via `CFBridgingRetain` before being inserted, and the
 * retained references are released immediately after insertion.
 *
 * ## Error handling
 * [save] throws [IllegalStateException] if the Keychain write fails.
 */
@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
actual class TokenStorage {

    /**
     * Persists [token] to the Keychain as a JSON-encoded generic password item.
     *
     * Uses an update-then-add strategy:
     * 1. Attempt `SecItemUpdate` on the existing item.
     * 2. If the item does not exist (`errSecItemNotFound`), add it with `SecItemAdd`.
     * 3. Any other non-success status throws [IllegalStateException].
     *
     * @throws IllegalStateException if the Keychain write fails.
     */
    actual fun save(token: AuthToken) {
        val json = Json.encodeToString(token)
        @Suppress("CAST_NEVER_SUCCEEDS")
        val nsJson = json as NSString
        val data: NSData = nsJson.dataUsingEncoding(NSUTF8StringEncoding)
            ?: error("TokenStorage.save: UTF-8 encoding of token JSON failed")

        // Build the base query identifying the existing item.
        val updateQuery = newCFDict()
        cfSet(updateQuery, kSecClass, kSecClassGenericPassword)
        cfSet(updateQuery, kSecAttrService, SERVICE)
        cfSet(updateQuery, kSecAttrAccount, ACCOUNT)

        // Build the attributes dict with the new value.
        val updateAttributes = newCFDict()
        cfSet(updateAttributes, kSecValueData, data)

        val updateStatus = SecItemUpdate(updateQuery, updateAttributes)
        CFBridgingRelease(updateQuery)
        CFBridgingRelease(updateAttributes)

        when (updateStatus) {
            errSecSuccess -> return

            errSecItemNotFound -> {
                // Item does not exist yet -- add it.
                val addQuery = newCFDict()
                cfSet(addQuery, kSecClass, kSecClassGenericPassword)
                cfSet(addQuery, kSecAttrService, SERVICE)
                cfSet(addQuery, kSecAttrAccount, ACCOUNT)
                cfSet(addQuery, kSecAttrAccessible, kSecAttrAccessibleAfterFirstUnlock)
                cfSet(addQuery, kSecValueData, data)

                val addStatus = SecItemAdd(addQuery, null)
                CFBridgingRelease(addQuery)

                // errSecDuplicateItem can occur in a race where another thread added
                // the item between our update attempt and this add. Treat it as success.
                check(addStatus == errSecSuccess || addStatus == errSecDuplicateItem) {
                    "TokenStorage.save: SecItemAdd failed with OSStatus $addStatus"
                }
            }

            else -> error("TokenStorage.save: SecItemUpdate failed with OSStatus $updateStatus")
        }
    }

    /** Returns the stored [AuthToken], or `null` if none is present or parsing fails. */
    actual fun load(): AuthToken? = memScoped {
        val query = newCFDict()
        cfSet(query, kSecClass, kSecClassGenericPassword)
        cfSet(query, kSecAttrService, SERVICE)
        cfSet(query, kSecAttrAccount, ACCOUNT)
        cfSet(query, kSecReturnData, kCFBooleanTrue)
        cfSet(query, kSecMatchLimit, kSecMatchLimitOne)

        val result = alloc<CFTypeRefVar>()
        val status = SecItemCopyMatching(query, result.ptr)
        CFBridgingRelease(query)

        if (status != errSecSuccess) return null

        val data = CFBridgingRelease(result.value) as? NSData ?: return null
        // NSString.create(data:encoding:) is the correct Kotlin/Native 2.x API
        // for decoding an NSData buffer to a String without raw pointer arithmetic.
        @Suppress("CAST_NEVER_SUCCEEDS")
        val json = NSString.create(data = data, encoding = NSUTF8StringEncoding)
            as? String ?: return null
        runCatching { Json.decodeFromString<AuthToken>(json) }.getOrNull()
    }

    /** Removes the stored token from the Keychain. */
    actual fun clear() {
        val query = newCFDict()
        cfSet(query, kSecClass, kSecClassGenericPassword)
        cfSet(query, kSecAttrService, SERVICE)
        cfSet(query, kSecAttrAccount, ACCOUNT)
        SecItemDelete(query)
        CFBridgingRelease(query)
        // Ignore the return value: errSecItemNotFound is expected when no token is stored.
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    /**
     * Creates an empty mutable CF dictionary with the standard type callbacks.
     * The caller must release the returned reference via [CFBridgingRelease].
     */
    private fun newCFDict(): CFMutableDictionaryRef = CFDictionaryCreateMutable(
        kCFAllocatorDefault,
        0,
        kCFTypeDictionaryKeyCallBacks.ptr,
        kCFTypeDictionaryValueCallBacks.ptr,
    )!!

    /**
     * Inserts [value] into [dict] under [key] using CF bridging.
     *
     * Both [key] and [value] are bridged to CF-retained references via
     * [CFBridgingRetain] and released immediately after the insertion.
     * This is safe because [CFDictionarySetValue] retains both key and value
     * internally (via the `kCFTypeDictionaryKeyCallBacks` retain callback).
     */
    private fun cfSet(dict: CFMutableDictionaryRef, key: Any?, value: Any?) {
        val cfKey = CFBridgingRetain(key)
        val cfValue = CFBridgingRetain(value)
        CFDictionarySetValue(dict, cfKey, cfValue)
        CFBridgingRelease(cfKey)
        CFBridgingRelease(cfValue)
    }

    private companion object {
        const val SERVICE = "com.pushup.auth"
        const val ACCOUNT = "auth_token"
    }
}
