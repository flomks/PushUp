package com.sinura.data.storage

import com.sinura.domain.model.AuthToken
import kotlinx.cinterop.BetaInteropApi
import kotlinx.cinterop.COpaquePointer
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
 * `COpaquePointer` values directly. Security constants (which are already CF
 * pointers) are passed directly via [cfSetCF], while Kotlin/ObjC objects
 * (Strings, NSData) are bridged via `CFBridgingRetain` in [cfSetObj].
 *
 * ## Error handling
 * [save] throws [IllegalStateException] if the Keychain write fails.
 */
@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
actual class TokenStorage {

    /**
     * Persists [token] to the Keychain as a JSON-encoded generic password item.
     *
     * Uses a delete-then-add strategy:
     * 1. Delete any existing item (ignore `errSecItemNotFound`).
     * 2. Add the new item with `SecItemAdd`.
     *
     * This avoids the `SecItemUpdate` pitfall where the update attributes
     * dictionary must not contain primary-key fields, and where passing CF
     * Security constants through `CFBridgingRetain` can produce invalid
     * references (OSStatus -50 / `errSecParam`).
     *
     * @throws IllegalStateException if the Keychain write fails.
     */
    actual fun save(token: AuthToken) {
        val json = Json.encodeToString(token)
        @Suppress("CAST_NEVER_SUCCEEDS")
        val nsJson = json as NSString
        val data: NSData = nsJson.dataUsingEncoding(NSUTF8StringEncoding)
            ?: error("TokenStorage.save: UTF-8 encoding of token JSON failed")

        // 1. Delete any existing item (ignore "not found").
        val deleteQuery = newCFDict()
        cfSetCF(deleteQuery, kSecClass, kSecClassGenericPassword)
        cfSetObj(deleteQuery, kSecAttrService, SERVICE)
        cfSetObj(deleteQuery, kSecAttrAccount, ACCOUNT)
        SecItemDelete(deleteQuery)
        // No need to check status -- errSecItemNotFound is fine.

        // 2. Add the new item.
        val addQuery = newCFDict()
        cfSetCF(addQuery, kSecClass, kSecClassGenericPassword)
        cfSetObj(addQuery, kSecAttrService, SERVICE)
        cfSetObj(addQuery, kSecAttrAccount, ACCOUNT)
        cfSetCF(addQuery, kSecAttrAccessible, kSecAttrAccessibleAfterFirstUnlock)
        cfSetObj(addQuery, kSecValueData, data)

        val addStatus = SecItemAdd(addQuery, null)

        check(addStatus == errSecSuccess) {
            "TokenStorage.save: SecItemAdd failed with OSStatus $addStatus"
        }
    }

    /** Returns the stored [AuthToken], or `null` if none is present or parsing fails. */
    actual fun load(): AuthToken? = memScoped {
        val query = newCFDict()
        cfSetCF(query, kSecClass, kSecClassGenericPassword)
        cfSetObj(query, kSecAttrService, SERVICE)
        cfSetObj(query, kSecAttrAccount, ACCOUNT)
        cfSetCF(query, kSecReturnData, kCFBooleanTrue)
        cfSetCF(query, kSecMatchLimit, kSecMatchLimitOne)

        val result = alloc<CFTypeRefVar>()
        val status = SecItemCopyMatching(query, result.ptr)

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
        cfSetCF(query, kSecClass, kSecClassGenericPassword)
        cfSetObj(query, kSecAttrService, SERVICE)
        cfSetObj(query, kSecAttrAccount, ACCOUNT)
        SecItemDelete(query)
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
     * Inserts a **CF-typed** [value] into [dict] under a **CF-typed** [key].
     *
     * Use this overload for Security framework constants (e.g. `kSecClass`,
     * `kSecClassGenericPassword`, `kSecAttrAccessible`, `kCFBooleanTrue`,
     * `kSecMatchLimit`, `kSecMatchLimitOne`, `kSecReturnData`) which are
     * already `CFTypeRef` pointers. Passing them through `CFBridgingRetain`
     * is incorrect because they are not Objective-C objects and the bridge
     * can produce invalid references (OSStatus -50 / `errSecParam`).
     */
    private fun cfSetCF(dict: CFMutableDictionaryRef, key: COpaquePointer?, value: COpaquePointer?) {
        CFDictionarySetValue(dict, key, value)
    }

    /**
     * Inserts a **Kotlin / Objective-C** [value] into [dict] under a
     * **CF-typed** [key].
     *
     * The [key] is a Security framework constant (`CFStringRef`) and is used
     * directly. The [value] is a Kotlin `String` or `NSData` that must be
     * bridged to a CF reference via [CFBridgingRetain]. The retained reference
     * is released immediately after insertion because [CFDictionarySetValue]
     * retains both key and value internally.
     */
    private fun cfSetObj(dict: CFMutableDictionaryRef, key: COpaquePointer?, value: Any?) {
        val cfValue = CFBridgingRetain(value)
        CFDictionarySetValue(dict, key, cfValue)
        CFBridgingRelease(cfValue)
    }

    private companion object {
        const val SERVICE = "com.sinura.auth"
        const val ACCOUNT = "auth_token"
    }
}
