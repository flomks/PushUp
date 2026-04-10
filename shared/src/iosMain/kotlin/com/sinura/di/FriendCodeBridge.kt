package com.sinura.di

import com.sinura.domain.model.FriendCode
import com.sinura.domain.model.FriendCodePrivacy
import com.sinura.domain.model.UseFriendCodeResult
import com.sinura.domain.repository.FriendCodeRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.koin.core.component.KoinComponent
import org.koin.core.component.get

/**
 * iOS-facing bridge that exposes friend code operations to Swift.
 *
 * Network/IO work runs on [Dispatchers.Default] to keep the main thread free.
 * All callbacks are dispatched back on [Dispatchers.Main] so Swift ViewModels
 * can update @Published properties directly without DispatchQueue.main.async.
 *
 * Error messages passed to [onError] are user-facing strings only --
 * internal exception details are never forwarded to the UI layer.
 */
object FriendCodeBridge : KoinComponent {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // =========================================================================
    // Get or create the caller's friend code
    // =========================================================================

    /**
     * Returns (or creates) the authenticated user's friend code.
     *
     * @param onResult Called on the main thread with the [FriendCode].
     * @param onError  Called on the main thread with a user-facing error message.
     */
    fun getMyFriendCode(
        onResult: (FriendCode) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val code = get<FriendCodeRepository>().getMyFriendCode()
                withContext(Dispatchers.Main) { onResult(code) }
            } catch (e: Exception) {
                val msg = "Could not load friend code: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }

    // =========================================================================
    // Update privacy setting
    // =========================================================================

    /**
     * Updates the privacy setting of the authenticated user's friend code.
     *
     * @param privacy  One of "auto_accept", "require_approval", or "inactive".
     * @param onResult Called on the main thread with the updated [FriendCode].
     * @param onError  Called on the main thread with a user-facing error message.
     */
    fun updatePrivacy(
        privacy: String,
        onResult: (FriendCode) -> Unit,
        onError: (String) -> Unit,
    ) {
        val privacyEnum = when (privacy.lowercase()) {
            "auto_accept"      -> FriendCodePrivacy.AUTO_ACCEPT
            "inactive"         -> FriendCodePrivacy.INACTIVE
            else               -> FriendCodePrivacy.REQUIRE_APPROVAL
        }
        scope.launch {
            try {
                val code = get<FriendCodeRepository>().updatePrivacy(privacyEnum)
                withContext(Dispatchers.Main) { onResult(code) }
            } catch (e: Exception) {
                val msg = "Could not update privacy: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }

    // =========================================================================
    // Reset code
    // =========================================================================

    /**
     * Generates a new random code for the authenticated user, invalidating the
     * previous one.
     *
     * @param onResult Called on the main thread with the updated [FriendCode].
     * @param onError  Called on the main thread with a user-facing error message.
     */
    fun resetCode(
        onResult: (FriendCode) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val code = get<FriendCodeRepository>().resetCode()
                withContext(Dispatchers.Main) { onResult(code) }
            } catch (e: Exception) {
                val msg = "Could not reset friend code: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }

    // =========================================================================
    // Use a friend code
    // =========================================================================

    /**
     * Uses a friend code entered or scanned by the authenticated user.
     *
     * @param code     The friend code string (case-insensitive; normalised server-side).
     * @param onResult Called on the main thread with the [UseFriendCodeResult].
     * @param onError  Called on the main thread with a user-facing error message.
     */
    fun useFriendCode(
        code: String,
        onResult: (UseFriendCodeResult) -> Unit,
        onError: (String) -> Unit,
    ) {
        scope.launch {
            try {
                val result = get<FriendCodeRepository>().useFriendCode(code)
                withContext(Dispatchers.Main) { onResult(result) }
            } catch (e: Exception) {
                val msg = "Could not use friend code: ${e.message ?: e::class.simpleName ?: "unknown error"}"
                withContext(Dispatchers.Main) { onError(msg) }
            }
        }
    }
}
