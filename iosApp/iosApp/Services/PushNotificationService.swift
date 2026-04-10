import Foundation
import os.log
import Shared

// MARK: - PushNotificationService

/// Registers the APNs device token with the PushUp backend so the server
/// can deliver push notifications (friend requests, friend accepted, etc.)
/// to this device.
///
/// **Flow**
/// 1. iOS calls `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`.
/// 2. AppDelegate converts the `Data` token to a hex string and calls
///    `PushNotificationService.shared.registerToken(_:)`.
/// 3. This service POSTs the token to `POST /api/device-token` with the
///    current user's JWT. If the user is not yet logged in, the token is
///    cached and sent on the next successful login.
///
/// **Retry on login**
/// Call `registerPendingTokenIfNeeded()` from `AuthViewModel` after a
/// successful login to flush any token that arrived before authentication.
final class PushNotificationService {

    static let shared = PushNotificationService()
    private init() {}

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.sinura",
        category: "PushNotifications"
    )

    /// Token received from APNs but not yet sent to the backend
    /// (e.g. arrived before the user logged in).
    private var pendingToken: String?
    private let authRetryDelaysNanoseconds: [UInt64] = [300_000_000, 1_000_000_000, 2_000_000_000]

    // MARK: - Public API

    /// Called by AppDelegate when iOS delivers a fresh APNs device token.
    ///
    /// Attempts to register the token immediately. If the user is not yet
    /// authenticated, the token is cached and sent after the next login.
    func registerToken(_ token: String) async {
        logger.debug("APNs token received: \(token.prefix(8))...")
        let outcome = await sendTokenToBackend(token)
        if outcome != .success {
            // Cache for retry after login.
            pendingToken = token
            logger.debug("Token cached for post-login registration.")
        }
    }

    /// Sends any cached token to the backend after a successful login.
    ///
    /// Call this from `AuthViewModel` immediately after `authState` transitions
    /// to `.authenticated`.
    func registerPendingTokenIfNeeded() async {
        guard let token = pendingToken else { return }
        for (attempt, delay) in authRetryDelaysNanoseconds.enumerated() {
            let outcome = await sendTokenToBackend(token)
            if outcome == .success {
                pendingToken = nil
                logger.info("Pending APNs token registered after login.")
                return
            }
            guard outcome == .deferredAuth else { break }
            logger.debug("APNs token registration deferred after login. Retrying attempt \(attempt + 2).")
            try? await Task.sleep(nanoseconds: delay)
        }
        logger.warning("Pending APNs token could not be registered after login. Will retry later.")
    }

    /// Retries a previously cached token when the app becomes active again.
    ///
    /// This covers the common case where APNs registration completed before
    /// auth/session restoration was fully ready, causing an early 401.
    func retryPendingTokenIfNeededOnAppActive() async {
        guard pendingToken != nil else { return }
        logger.debug("Retrying pending APNs token registration after app became active.")
        await registerPendingTokenIfNeeded()
    }

    // MARK: - Private

    /// POSTs the device token to `POST /api/device-token`.
    ///
    /// Returns a detailed outcome so auth timing problems can be retried
    /// after login instead of being treated as hard backend failures.
    private func sendTokenToBackend(_ token: String) async -> RegistrationOutcome {
        guard let backendURL = backendBaseURL() else {
            logger.warning("BackendBaseURL not configured -- token registration skipped.")
            return .failed
        }

        // Get the current JWT. If the user is not logged in, this will be nil.
        guard let jwt = await currentJWT() else {
            logger.debug("No JWT available -- token registration deferred.")
            return .deferredAuth
        }

        guard let url = URL(string: "\(backendURL)/api/device-token") else {
            logger.error("Invalid backend URL: \(backendURL)/api/device-token")
            return .failed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let body = ["token": token, "platform": "apns"]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .failed
        }
        request.httpBody = bodyData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200 {
                logger.info("APNs token registered with backend.")
                return .success
            } else if statusCode == 401 || statusCode == 403 {
                logger.warning("Backend returned \(statusCode) for device-token registration. Deferring retry until auth is stable.")
                return .deferredAuth
            } else {
                logger.warning("Backend returned \(statusCode) for device-token registration.")
                return .failed
            }
        } catch {
            logger.error("Device token registration request failed: \(error.localizedDescription)")
            return .failed
        }
    }

    /// Reads the backend base URL from Info.plist (key: BackendBaseURL).
    private func backendBaseURL() -> String? {
        let url = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String
        return url?.isEmpty == false ? url : nil
    }

    /// Returns the current user's JWT access token, or nil if not logged in.
    ///
    /// Reads directly from the KMP Keychain-backed TokenStorage via DIHelper
    /// to avoid an extra network round-trip.
    private func currentJWT() async -> String? {
        return await Task.detached(priority: .userInitiated) {
            DIHelper.shared.getAccessToken()
        }.value
    }
}

private enum RegistrationOutcome {
    case success
    case deferredAuth
    case failed
}
