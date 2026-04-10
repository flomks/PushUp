package com.sinura.domain.usecase.auth

import com.sinura.domain.repository.AuthRepository

/**
 * Use-case: Sign out the current user.
 *
 * Clears the stored authentication token from secure local storage
 * (iOS Keychain / Android EncryptedSharedPreferences). Optionally also
 * deletes the local user data from the database.
 *
 * This use-case does **not** call the Supabase server-side sign-out endpoint.
 * The token is simply discarded locally -- it will expire naturally on the
 * server. This design avoids a network dependency for logout and ensures
 * logout works even when the device is offline.
 *
 * @property authRepository The repository that manages token storage and local data.
 */
class LogoutUseCase(
    private val authRepository: AuthRepository,
) {

    /**
     * Signs out the current user.
     *
     * @param clearLocalData When `true`, the local [com.sinura.domain.model.User] record
     *   is also cleared from the database. Defaults to `false` to preserve offline data
     *   (e.g. workout history) in case the user logs back in later.
     */
    suspend operator fun invoke(clearLocalData: Boolean = false) {
        authRepository.logout(clearLocalData)
    }
}
