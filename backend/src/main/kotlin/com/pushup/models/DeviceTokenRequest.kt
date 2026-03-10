package com.pushup.models

import kotlinx.serialization.Serializable

/**
 * Request body for POST /api/device-token.
 *
 * @property token    The APNs device token hex string returned by iOS.
 * @property platform "apns" for iOS (default). Reserved for future "fcm" (Android).
 */
@Serializable
data class RegisterDeviceTokenRequest(
    val token: String,
    val platform: String = "apns",
)

/**
 * Response body for POST /api/device-token.
 */
@Serializable
data class RegisterDeviceTokenResponse(
    val success: Boolean,
)
