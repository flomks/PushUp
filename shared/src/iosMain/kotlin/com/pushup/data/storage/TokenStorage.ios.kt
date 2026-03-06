package com.pushup.data.storage

import com.pushup.domain.model.AuthToken
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.value
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import platform.CoreFoundation.CFTypeRefVar
import platform.Foundation.CFBridgingRelease
import platform.Foundation.NSData
import platform.Foundation.NSMutableDictionary
import platform.Foundation.NSString
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.dataUsingEncoding
import platform.Foundation.stringWithCString
import platform.Security.SecItemAdd
import platform.Security.SecItemCopyMatching
import platform.Security.SecItemDelete
import platform.Security.SecItemUpdate
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
 * ## Setup
 * Bind this class in your Koin iOS module:
 * ```kotlin
 * single { TokenStorage() }
 * ```
 */
@OptIn(ExperimentalForeignApi::class)
actual class TokenStorage {

    /** Persists [token] to the Keychain as a JSON-encoded generic password item. */
    actual fun save(token: AuthToken) {
        val json = Json.encodeToString(token)
        val data = (json as NSString).dataUsingEncoding(NSUTF8StringEncoding) ?: return

        // Try to update an existing item first.
        val updateQuery = NSMutableDictionary().apply {
            setObject(kSecClassGenericPassword, forKey = kSecClass as NSString)
            setObject(SERVICE, forKey = kSecAttrService as NSString)
            setObject(ACCOUNT, forKey = kSecAttrAccount as NSString)
        }
        val updateAttributes = NSMutableDictionary().apply {
            setObject(data, forKey = kSecValueData as NSString)
        }
        @Suppress("UNCHECKED_CAST")
        val updateStatus = SecItemUpdate(
            updateQuery as platform.CoreFoundation.CFDictionaryRef,
            updateAttributes as platform.CoreFoundation.CFDictionaryRef,
        )

        if (updateStatus == errSecSuccess) return

        // Item did not exist -- add it.
        val addQuery = NSMutableDictionary().apply {
            setObject(kSecClassGenericPassword, forKey = kSecClass as NSString)
            setObject(SERVICE, forKey = kSecAttrService as NSString)
            setObject(ACCOUNT, forKey = kSecAttrAccount as NSString)
            setObject(kSecAttrAccessibleAfterFirstUnlock, forKey = kSecAttrAccessible as NSString)
            setObject(data, forKey = kSecValueData as NSString)
        }
        @Suppress("UNCHECKED_CAST")
        SecItemAdd(addQuery as platform.CoreFoundation.CFDictionaryRef, null)
    }

    /** Returns the stored [AuthToken], or `null` if none is present or parsing fails. */
    actual fun load(): AuthToken? = memScoped {
        val query = NSMutableDictionary().apply {
            setObject(kSecClassGenericPassword, forKey = kSecClass as NSString)
            setObject(SERVICE, forKey = kSecAttrService as NSString)
            setObject(ACCOUNT, forKey = kSecAttrAccount as NSString)
            setObject(true, forKey = kSecReturnData as NSString)
            setObject(kSecMatchLimitOne, forKey = kSecMatchLimit as NSString)
        }
        val result = alloc<CFTypeRefVar>()
        @Suppress("UNCHECKED_CAST")
        val status = SecItemCopyMatching(
            query as platform.CoreFoundation.CFDictionaryRef,
            result.ptr,
        )
        if (status != errSecSuccess) return null

        val data = CFBridgingRelease(result.value) as? NSData ?: return null
        val json = NSString.stringWithCString(
            cString = data.bytes?.reinterpret() ?: return null,
            encoding = NSUTF8StringEncoding,
        ) as? String ?: return null
        runCatching { Json.decodeFromString<AuthToken>(json) }.getOrNull()
    }

    /** Removes the stored token from the Keychain. */
    actual fun clear() {
        val query = NSMutableDictionary().apply {
            setObject(kSecClassGenericPassword, forKey = kSecClass as NSString)
            setObject(SERVICE, forKey = kSecAttrService as NSString)
            setObject(ACCOUNT, forKey = kSecAttrAccount as NSString)
        }
        @Suppress("UNCHECKED_CAST")
        SecItemDelete(query as platform.CoreFoundation.CFDictionaryRef)
    }

    private companion object {
        const val SERVICE = "com.pushup.auth"
        const val ACCOUNT = "auth_token"
    }
}
