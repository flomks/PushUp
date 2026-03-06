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
 * in `NSMutableDictionary` (which requires `NSCopyingProtocol`), and they cannot
 * be cast to `NSString` (the compiler correctly rejects such casts as impossible).
 *
 * The correct approach is to build the query dictionaries using the CoreFoundation
 * `CFDictionaryCreateMutable` / `CFDictionarySetValue` API, which operates on
 * `COpaquePointer` values directly -- no NS bridging required. The resulting
 * `CFMutableDictionaryRef` is then passed directly to the Security framework
 * functions, which accept it as `CFDictionaryRef`.
 *
 * String values (service name, account name) are bridged from Kotlin `String`
 * to `CFTypeRef` via `CFBridgingRetain`, and the resulting retained reference
 * is released after the dictionary is used.
 *
 * ## Error handling
 * [save] throws [IllegalStateException] if the Keychain write fails for any
 * reason (e.g. device locked, Keychain unavailable).
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
        val data: NSData = (json as NSString).dataUsingEncoding(NSUTF8StringEncoding)
            ?: error("TokenStorage.save: UTF-8 encoding of token JSON failed")

        val updateQuery = buildBaseQuery()
        val updateAttributes = cfDict {
            set(kSecValueData, data)
        }

        val updateStatus = SecItemUpdate(updateQuery, updateAttributes)
        cfRelease(updateQuery)
        cfRelease(updateAttributes)

        when (updateStatus) {
            errSecSuccess -> return

            errSecItemNotFound -> {
                val addQuery = buildBaseQuery().also { dict ->
                    set(dict, kSecAttrAccessible, kSecAttrAccessibleAfterFirstUnlock)
                    set(dict, kSecValueData, data)
                }
                val addStatus = SecItemAdd(addQuery, null)
                cfRelease(addQuery)
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
        val query = buildBaseQuery().also { dict ->
            set(dict, kSecReturnData, kCFBooleanTrue)
            set(dict, kSecMatchLimit, kSecMatchLimitOne)
        }
        val result = alloc<CFTypeRefVar>()
        val status = SecItemCopyMatching(query, result.ptr)
        cfRelease(query)

        if (status != errSecSuccess) return null

        val data = CFBridgingRelease(result.value) as? NSData ?: return null
        // NSString.create(data:encoding:) is the correct Kotlin/Native 2.x API
        // for decoding an NSData buffer to a String without raw pointer arithmetic.
        val json = NSString.create(data = data, encoding = NSUTF8StringEncoding)
            as? String ?: return null
        runCatching { Json.decodeFromString<AuthToken>(json) }.getOrNull()
    }

    /** Removes the stored token from the Keychain. */
    actual fun clear() {
        val query = buildBaseQuery()
        SecItemDelete(query)
        cfRelease(query)
        // Ignore the return value: errSecItemNotFound is expected when no token is stored.
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    /**
     * Creates a mutable CF dictionary pre-populated with the base Keychain query
     * attributes that identify the token item (class, service, account).
     *
     * The caller is responsible for releasing the returned dictionary via [cfRelease].
     */
    private fun buildBaseQuery(): CFMutableDictionaryRef {
        val dict = cfDict()
        set(dict, kSecClass, kSecClassGenericPassword)
        set(dict, kSecAttrService, SERVICE)
        set(dict, kSecAttrAccount, ACCOUNT)
        return dict
    }

    /**
     * Creates an empty mutable CF dictionary and optionally populates it via [block].
     *
     * The caller is responsible for releasing the returned dictionary via [cfRelease].
     */
    private fun cfDict(block: CFMutableDictionaryRef.() -> Unit = {}): CFMutableDictionaryRef =
        CFDictionaryCreateMutable(
            kCFAllocatorDefault,
            0,
            kCFTypeDictionaryKeyCallBacks.ptr,
            kCFTypeDictionaryValueCallBacks.ptr,
        )!! .also { it.block() }

    /**
     * Sets a CF dictionary entry where both key and value are CF/Security constants
     * (typed as `COpaquePointer` or `CPointer<*>`).
     *
     * This overload handles the common case where both key and value are already
     * CF-typed pointers -- no bridging needed.
     */
    private fun set(dict: CFMutableDictionaryRef, key: Any?, value: Any?) {
        val cfKey = CFBridgingRetain(key)
        val cfValue = CFBridgingRetain(value)
        CFDictionarySetValue(dict, cfKey, cfValue)
        CFBridgingRelease(cfKey)
        CFBridgingRelease(cfValue)
    }

    /**
     * Sets a CF dictionary entry where the value is a Kotlin [String].
     *
     * The string is bridged to a CF-retained `CFStringRef` via [CFBridgingRetain],
     * set in the dictionary, then released.
     */
    private fun set(dict: CFMutableDictionaryRef, key: Any?, value: String) {
        val cfKey = CFBridgingRetain(key)
        val cfValue = CFBridgingRetain(value)
        CFDictionarySetValue(dict, cfKey, cfValue)
        CFBridgingRelease(cfKey)
        CFBridgingRelease(cfValue)
    }

    /**
     * Sets a CF dictionary entry where the value is an [NSData] object.
     */
    private fun set(dict: CFMutableDictionaryRef, key: Any?, value: NSData) {
        val cfKey = CFBridgingRetain(key)
        val cfValue = CFBridgingRetain(value)
        CFDictionarySetValue(dict, cfKey, cfValue)
        CFBridgingRelease(cfKey)
        CFBridgingRelease(cfValue)
    }

    /** Releases a CF object obtained from [cfDict] or [buildBaseQuery]. */
    private fun cfRelease(ref: CFMutableDictionaryRef) {
        CFBridgingRelease(ref)
    }

    private companion object {
        const val SERVICE = "com.pushup.auth"
        const val ACCOUNT = "auth_token"
    }
}
