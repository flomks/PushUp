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

// MARK: - AuthService

/// Swift-side wrapper around KMP auth operations.
///
/// Uses SafeAuthBridge (Kotlin object) which catches ALL exceptions in Kotlin
/// and returns SafeAuthResult. This prevents Kotlin exceptions from crashing
/// the iOS app when they cross the Kotlin/Swift boundary.
@MainActor
final class AuthService {

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

    // MARK: - Private

    /// Bridges a SafeAuthBridge completionHandler call to async/await.
    ///
    /// SafeAuthBridge methods NEVER throw — they always return SafeAuthResult.
    /// The completionHandler signature is: (SafeAuthResult?, Error?) -> Void
    /// Since SafeAuthBridge catches all exceptions, error is always nil.
    private func callSafeBridge(
        _ call: @escaping (@escaping (SafeAuthResult?, Error?) -> Void) -> Void
    ) async -> AuthServiceResult {
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
            // But just in case:
            return .failure("An unexpected error occurred: \(error.localizedDescription)")
        }
    }
}
