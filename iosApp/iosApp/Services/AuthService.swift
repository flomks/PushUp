import Foundation
import Shared

// MARK: - AuthServiceResult

/// Result of an auth operation. Never throws — errors are captured as messages.
struct AuthServiceResult {
    let user: User?
    let errorMessage: String?
    var isSuccess: Bool { user != nil }

    static func success(_ user: User) -> AuthServiceResult {
        AuthServiceResult(user: user, errorMessage: nil)
    }
    static func failure(_ message: String) -> AuthServiceResult {
        AuthServiceResult(user: nil, errorMessage: message)
    }
}

// MARK: - UsernameCheckResult

/// Result of a username availability check.
struct UsernameCheckResult {
    let available: Bool
    let errorMessage: String?
}

// MARK: - AuthService

/// Swift-side wrapper around KMP auth operations.
///
/// Uses SafeAuthBridge (Kotlin object) which catches ALL exceptions in Kotlin
/// and returns SafeAuthResult. This prevents Kotlin exceptions from crashing
/// the iOS app when they cross the Kotlin/Swift boundary.
///
/// All methods are NOT @MainActor — they run on a background thread so that
/// network I/O does not block the main thread and freeze the UI.
/// Callers that need to update UI state must hop back to @MainActor themselves.
final class AuthService: Sendable {

    static let shared = AuthService()
    private init() {}

    // MARK: - Email / Password

    func loginWithEmail(email: String, password: String) async -> AuthServiceResult {
        await callSafeBridge { handler in
            SafeAuthBridge.shared.safeLoginWithEmail(
                email: email,
                password: password,
                completionHandler: handler
            )
        }
    }

    func registerWithEmail(email: String, password: String) async -> AuthServiceResult {
        await callSafeBridge { handler in
            SafeAuthBridge.shared.safeRegisterWithEmail(
                email: email,
                password: password,
                completionHandler: handler
            )
        }
    }

    // MARK: - Apple

    func loginWithApple(idToken: String) async -> AuthServiceResult {
        await callSafeBridge { handler in
            SafeAuthBridge.shared.safeLoginWithApple(
                idToken: idToken,
                completionHandler: handler
            )
        }
    }

    // MARK: - Google (PKCE)

    func loginWithGoogleOAuthCode(code: String) async -> AuthServiceResult {
        await callSafeBridge { handler in
            SafeAuthBridge.shared.safeLoginWithGoogleOAuthCode(
                code: code,
                completionHandler: handler
            )
        }
    }

    // MARK: - Google (Implicit Flow — tokens in URL fragment)

    func storeImplicitSession(
        accessToken: String,
        refreshToken: String,
        userId: String,
        userEmail: String?,
        expiresIn: Int64
    ) async -> AuthServiceResult {
        // Use the SafeAuthBridge suspend function which stores the token AND
        // creates the User record in the local database (via AuthRepository).
        // The previous implementation only stored the token, leaving the User
        // record missing — causing empty profile data after Google login.
        await callSafeBridge { handler in
            SafeAuthBridge.shared.safeLoginWithImplicitTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                userId: userId,
                userEmail: userEmail,
                expiresIn: expiresIn,
                completionHandler: handler
            )
        }
    }

    // MARK: - Session

    func getCurrentUser() async -> User? {
        let result = await callSafeBridge { handler in
            SafeAuthBridge.shared.safeGetCurrentUser(completionHandler: handler)
        }
        return result.user
    }

    func logout() async {
        _ = await callSafeBridge { handler in
            SafeAuthBridge.shared.safeLogout(completionHandler: handler)
        }
    }

    /// Updates the display name of the currently authenticated user in the local DB.
    ///
    /// Called after the user completes the "Choose your display name" screen on
    /// first social sign-in. Writes to the local SQLDelight DB immediately so
    /// the name is never NULL even if the app is killed before cloud sync runs.
    func updateDisplayName(_ name: String) async -> AuthServiceResult {
        await callSafeBridge { handler in
            SafeAuthBridge.shared.safeUpdateDisplayName(
                displayName: name,
                completionHandler: handler
            )
        }
    }

    // MARK: - Username

    /// Checks whether a username is available (not taken by another user).
    ///
    /// Returns a UsernameCheckResult with available = true if the username is free.
    func checkUsernameAvailability(_ username: String) async -> UsernameCheckResult {
        return await Task.detached(priority: .userInitiated) {
            do {
                let result: SafeUsernameCheckResult = try await withCheckedThrowingContinuation { continuation in
                    let lock = NSLock()
                    var hasResumed = false
                    SafeAuthBridge.shared.safeCheckUsernameAvailability(
                        username: username
                    ) { result, error in
                        lock.lock()
                        guard !hasResumed else { lock.unlock(); return }
                        hasResumed = true
                        lock.unlock()
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let result = result {
                            continuation.resume(returning: result)
                        } else {
                            continuation.resume(throwing: NSError(
                                domain: "AuthService",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "KMP returned nil"]
                            ))
                        }
                    }
                }
                return UsernameCheckResult(available: result.available, errorMessage: result.errorMessage)
            } catch {
                return UsernameCheckResult(available: false, errorMessage: error.localizedDescription)
            }
        }.value
    }

    /// Sets the username for the currently authenticated user.
    ///
    /// Validates the username, calls the backend to enforce uniqueness, and
    /// persists the username locally.
    func setUsername(_ username: String) async -> AuthServiceResult {
        await callSafeBridge { handler in
            SafeAuthBridge.shared.safeSetUsername(
                username: username,
                completionHandler: handler
            )
        }
    }

    // MARK: - Cloud Profile Merge

    /// Fetches the user profile from the cloud and merges any server-side
    /// username / display name into the local database.
    ///
    /// Used during session restore: when the local DB has been wiped (e.g. app
    /// reinstall) but the Keychain token still exists, the local User record is
    /// recreated with `username = nil`. This method checks whether the server
    /// already has a username for this user and, if so, persists it locally so
    /// the "Choose your username" screen is skipped.
    func fetchAndMergeCloudProfile() async -> AuthServiceResult {
        await callSafeBridge { handler in
            SafeAuthBridge.shared.safeFetchAndMergeCloudProfile(completionHandler: handler)
        }
    }

    // MARK: - Avatar

    /// Updates the avatar URL for the currently authenticated user.
    /// Pass nil to clear the avatar.
    func updateAvatar(_ avatarUrl: String?) async -> AuthServiceResult {
        await callSafeBridge { handler in
            SafeAuthBridge.shared.safeUpdateAvatar(
                avatarUrl: avatarUrl,
                completionHandler: handler
            )
        }
    }

    /// Updates the avatar visibility setting.
    /// - Parameter visibility: One of "everyone", "friends_only", "nobody"
    func updateAvatarVisibility(_ visibility: String) async -> AuthServiceResult {
        await callSafeBridge { handler in
            SafeAuthBridge.shared.safeUpdateAvatarVisibility(
                visibility: visibility,
                completionHandler: handler
            )
        }
    }

    // MARK: - Privacy Settings

    /// Returns whether the current user has opted in to email-based search.
    func getSearchableByEmail() async -> Bool {
        return await Task.detached(priority: .userInitiated) {
            do {
                return try await withCheckedThrowingContinuation { continuation in
                    let lock = NSLock()
                    var hasResumed = false
                    SafeAuthBridge.shared.safeGetSearchableByEmail { result, error in
                        lock.lock()
                        guard !hasResumed else { lock.unlock(); return }
                        hasResumed = true
                        lock.unlock()
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: result?.boolValue ?? false)
                        }
                    }
                }
            } catch {
                return false
            }
        }.value
    }

    /// Updates the searchable-by-email privacy setting.
    func updateSearchableByEmail(_ enabled: Bool) async -> AuthServiceResult {
        await callSafeBridge { handler in
            SafeAuthBridge.shared.safeUpdateSearchableByEmail(
                enabled: enabled,
                completionHandler: handler
            )
        }
    }

    // MARK: - Private

    /// Bridges a SafeAuthBridge completionHandler call to async/await.
    ///
    /// Explicitly runs on a background thread (Task.detached) so that the
    /// KMP network I/O does not block the main thread and freeze the UI.
    ///
    /// SafeAuthBridge methods NEVER throw — they always return SafeAuthResult.
    /// The completionHandler signature is: (SafeAuthResult?, Error?) -> Void
    /// Since SafeAuthBridge catches all exceptions, error is always nil.
    private func callSafeBridge(
        _ call: @escaping (@escaping (SafeAuthResult?, Error?) -> Void) -> Void
    ) async -> AuthServiceResult {
        // Hop off the main thread so network I/O does not block the UI.
        return await Task.detached(priority: .userInitiated) {
            do {
                let kmpResult: SafeAuthResult = try await withCheckedThrowingContinuation { continuation in
                    let lock = NSLock()
                    var hasResumed = false
                    call { result, error in
                        lock.lock()
                        guard !hasResumed else { lock.unlock(); return }
                        hasResumed = true
                        lock.unlock()
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let result = result {
                            continuation.resume(returning: result)
                        } else {
                            continuation.resume(throwing: NSError(
                                domain: "AuthService",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "KMP returned nil"]
                            ))
                        }
                    }
                }
                // Map SafeAuthResult -> AuthServiceResult
                if let user = kmpResult.user {
                    return .success(user)
                } else if let errorMsg = kmpResult.errorMessage {
                    return .failure(errorMsg)
                } else {
                    // No user and no error — e.g. getCurrentUser when not logged in
                    return AuthServiceResult(user: nil, errorMessage: nil)
                }
            } catch {
                // This should never happen since SafeAuthBridge catches all exceptions.
                return .failure("An unexpected error occurred: \(error.localizedDescription)")
            }
        }.value
    }
}
