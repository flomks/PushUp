package com.pushup.data.storage

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.pushup.domain.model.AuthToken
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Android implementation of [TokenStorage] backed by [EncryptedSharedPreferences].
 *
 * The [AuthToken] is serialised to JSON and stored under [KEY_TOKEN] in an
 * [EncryptedSharedPreferences] file. The encryption key is stored in the
 * Android Keystore and the value is AES-256-GCM encrypted.
 *
 * ## Write durability
 * [save] uses [SharedPreferences.Editor.commit] (synchronous) rather than
 * [SharedPreferences.Editor.apply] (asynchronous). Token persistence is a
 * security-critical operation: if the process is killed immediately after
 * [save] returns, the token must already be on disk so the user is not
 * unexpectedly logged out on next launch. The synchronous write adds only a
 * few milliseconds of latency and is called at most once per login.
 *
 * [clear] uses [apply] because a failed clear is less dangerous than a failed
 * save -- the token will expire naturally on the server.
 *
 * ## Setup
 * Bind this class in your Koin Android module:
 * ```kotlin
 * single { TokenStorage(context = androidContext()) }
 * ```
 *
 * @param context Application [Context] used to create the [EncryptedSharedPreferences].
 */
actual class TokenStorage(context: Context) {

    private val prefs: SharedPreferences by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        EncryptedSharedPreferences.create(
            context,
            PREFS_FILE_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    /**
     * Persists [token] to [EncryptedSharedPreferences] as a JSON string.
     *
     * Uses [SharedPreferences.Editor.commit] (synchronous) to guarantee the
     * token is flushed to disk before this function returns.
     *
     * @throws IllegalStateException if the write fails (commit returns false).
     */
    actual fun save(token: AuthToken) {
        val committed = prefs.edit()
            .putString(KEY_TOKEN, Json.encodeToString(token))
            .commit()
        check(committed) { "TokenStorage.save: EncryptedSharedPreferences commit failed" }
    }

    /** Returns the stored [AuthToken], or `null` if none is present or parsing fails. */
    actual fun load(): AuthToken? {
        val json = prefs.getString(KEY_TOKEN, null) ?: return null
        return runCatching { Json.decodeFromString<AuthToken>(json) }.getOrNull()
    }

    /** Removes the stored token from [EncryptedSharedPreferences]. */
    actual fun clear() {
        prefs.edit().remove(KEY_TOKEN).apply()
    }

    private companion object {
        const val PREFS_FILE_NAME = "pushup_secure_prefs"
        const val KEY_TOKEN = "auth_token"
    }
}
