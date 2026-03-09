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

/// Swift-side wrapper around KMP auth use cases.
///
/// All methods are safe — they NEVER throw. Kotlin exceptions are caught
/// here in Swift and mapped to user-friendly error messages.
///
/// KMP suspend functions are exported as completionHandler-based callbacks:
///   func invoke(..., completionHandler: @escaping (T?, Error?) -> Void)
/// We bridge them to async/await using withKMPAuthSuspend().
@MainActor
final class AuthService {

    static let shared = AuthService()
    private init() {}

    // MARK: - Email / Password

    func loginWithEmail(email: String, password: String) async -> AuthServiceResult {
        await safeCall {
            try await withKMPAuthSuspend { handler in
                DIHelper.shared.loginWithEmailUseCase().invoke(
                    email: email,
                    password: password,
                    completionHandler: handler
                )
            }
        }
    }

    func registerWithEmail(email: String, password: String) async -> AuthServiceResult {
        await safeCall {
            try await withKMPAuthSuspend { handler in
                DIHelper.shared.registerWithEmailUseCase().invoke(
                    email: email,
                    password: password,
                    completionHandler: handler
                )
            }
        }
    }

    // MARK: - Apple

    func loginWithApple(idToken: String) async -> AuthServiceResult {
        await safeCall {
            try await withKMPAuthSuspend { handler in
                DIHelper.shared.loginWithAppleUseCase().invoke(
                    idToken: idToken,
                    completionHandler: handler
                )
            }
        }
    }

    // MARK: - Google

    func loginWithGoogleOAuthCode(code: String) async -> AuthServiceResult {
        await safeCall {
            try await withKMPAuthSuspend { handler in
                DIHelper.shared.loginWithGoogleUseCase().invokeWithOAuthCode(
                    code: code,
                    completionHandler: handler
                )
            }
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
        // DIHelper.loginWithImplicitTokens is a suspend function on a Kotlin object.
        // Kotlin/Native exports it as a completionHandler-based method.
        await safeCall {
            try await withKMPAuthSuspend { (handler: @escaping (User?, Error?) -> Void) in
                DIHelper.shared.loginWithImplicitTokens(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    userId: userId,
                    userEmail: userEmail,
                    expiresIn: expiresIn,
                    completionHandler: handler
                )
            }
        }
    }

    // MARK: - Session

    func getCurrentUser() async -> User? {
        do {
            return try await withKMPAuthSuspend { handler in
                DIHelper.shared.getCurrentUserUseCase().invoke(completionHandler: handler)
            }
        } catch {
            return nil
        }
    }

    func logout() async {
        // LogoutUseCase.invoke returns Unit (Void in Swift).
        // We use a simple semaphore bridge since withKMPAuthSuspend expects a non-Void return.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DIHelper.shared.logoutUseCase().invoke(clearLocalData: true) { error in
                // Ignore errors — best-effort logout
                continuation.resume()
            }
        }
    }

    // MARK: - Private

    private func safeCall(_ block: () async throws -> User) async -> AuthServiceResult {
        do {
            let user = try await block()
            return .success(user)
        } catch let error as AuthException {
            return .failure(mapAuthException(error))
        } catch let error as KotlinThrowable {
            return .failure(mapKotlinError(error))
        } catch {
            return .failure(mapSwiftError(error))
        }
    }

    private func mapAuthException(_ error: AuthException) -> String {
        let typeName = String(describing: type(of: error)).lowercased()
        let msg = error.message ?? ""
        if typeName.contains("invalidcredentials") { return "Email or password is incorrect." }
        if typeName.contains("emailalreadyinuse") { return "This email address is already in use." }
        if typeName.contains("weakpassword") { return "Password is too weak." }
        if typeName.contains("invalidemail") { return "Please enter a valid email address." }
        if typeName.contains("sessionexpired") { return "Your session has expired. Please sign in again." }
        if typeName.contains("networkerror") { return "Network error. Please check your connection." }
        if typeName.contains("servererror") { return "Server error. Please try again." }
        return msg.isEmpty ? "Authentication failed." : msg
    }

    private func mapKotlinError(_ error: KotlinThrowable) -> String {
        let msg = (error.message ?? "").lowercased()
        if msg.contains("invalid") && msg.contains("credential") { return "Email or password is incorrect." }
        if msg.contains("network") || msg.contains("connect") { return "Network error. Please check your connection." }
        if msg.contains("email") && msg.contains("confirm") { return "Please confirm your email address first." }
        return "An error occurred. Please try again."
    }

    private func mapSwiftError(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("network") || msg.contains("connect") { return "Network error. Please check your connection." }
        return "An error occurred. Please try again."
    }
}

// MARK: - KMP Suspend Bridge

/// Bridges a KMP completionHandler-based callback to Swift async/await.
///
/// KMP suspend functions are exported to Swift as:
///   func invoke(..., completionHandler: @escaping (T?, Error?) -> Void)
private func withKMPAuthSuspend<T>(
    _ body: @escaping (@escaping (T?, Error?) -> Void) -> Void
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let lock = NSLock()
        var hasResumed = false
        body { result, error in
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
                    userInfo: [NSLocalizedDescriptionKey: "KMP returned nil without error"]
                ))
            }
        }
    }
}
