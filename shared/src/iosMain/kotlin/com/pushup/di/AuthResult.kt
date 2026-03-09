package com.pushup.di

import com.pushup.domain.model.User

/**
 * A simple result wrapper for auth operations exposed to Swift.
 *
 * Kotlin/Native suspend functions that throw exceptions can crash the iOS app
 * because the exception does not cross the Kotlin/Swift boundary cleanly.
 * This wrapper ensures exceptions NEVER escape to Swift — they are captured
 * as [errorMessage] instead.
 *
 * Usage from Swift:
 * ```swift
 * let result = await DIHelper.shared.safeLoginWithEmail(email: "...", password: "...")
 * if let user = result.user {
 *     // success
 * } else {
 *     errorMessage = result.errorMessage ?? "Unknown error"
 * }
 * ```
 */
data class AuthResult(
    val user: User? = null,
    val errorMessage: String? = null,
) {
    val isSuccess: Boolean get() = user != null
}
