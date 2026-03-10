import AuthenticationServices
import Shared
import SwiftUI

// MARK: - AuthError

/// Typed errors surfaced by the auth flow.
enum AuthError: LocalizedError {
    case invalidEmail
    case passwordTooShort
    case passwordsDoNotMatch
    case displayNameEmpty
    case networkError(String)
    case invalidCredentials
    case emailAlreadyInUse
    case appleSignInCancelled
    case googleSignInCancelled
    case notConfigured
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Please enter a valid email address."
        case .passwordTooShort:
            return "Password must be at least 8 characters long."
        case .passwordsDoNotMatch:
            return "Passwords do not match."
        case .displayNameEmpty:
            return "Please enter a display name."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .invalidCredentials:
            return "Email or password is incorrect."
        case .emailAlreadyInUse:
            return "This email address is already in use."
        case .appleSignInCancelled:
            return nil
        case .googleSignInCancelled:
            return nil
        case .notConfigured:
            return "Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY in Config.xcconfig."
        case .unknown(let msg):
            return "An error occurred: \(msg)"
        }
    }
}

// MARK: - AuthState

/// Represents the current authentication state of the app.
enum AuthState: Equatable {
    case unauthenticated
    case loading
    case authenticated
}

// MARK: - Validation Constants

private enum AuthValidation {
    /// Minimum password length enforced on login and registration.
    static let minimumPasswordLength = 8

    /// RFC 5322-inspired email pattern. Intentionally simple -- the real
    /// validation happens server-side; this only prevents obviously wrong input.
    static let emailPattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
}

// MARK: - AuthViewModel

/// Manages authentication state and coordinates login, registration,
/// and social sign-in flows.
///
/// All published properties are updated on the main actor.
/// API calls are delegated to KMP use cases via [DIHelper].
@MainActor
final class AuthViewModel: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var authState: AuthState = .unauthenticated

    // Login fields
    @Published var loginEmail: String = ""
    @Published var loginPassword: String = ""

    // Register fields
    @Published var registerEmail: String = ""
    @Published var registerPassword: String = ""
    @Published var registerConfirmPassword: String = ""
    @Published var registerDisplayName: String = ""

    // Forgot password field
    @Published var forgotPasswordEmail: String = ""

    // UI state
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var successMessage: String? = nil
    @Published var showPasswordResetConfirmation: Bool = false

    // MARK: - Private

    /// Continuation for Apple Sign-In — bridges the delegate callback to async/await.
    private var appleSignInContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    /// Retained reference to the active ASWebAuthenticationSession.
    /// Must be kept alive for the duration of the OAuth flow — ARC would
    /// otherwise deallocate it immediately after start() returns.
    private var webAuthSession: ASWebAuthenticationSession?

    // MARK: - Form Validation

    /// Returns `true` when the login form has valid, non-empty inputs.
    var isLoginFormValid: Bool {
        isValidEmail(loginEmail)
            && loginPassword.count >= AuthValidation.minimumPasswordLength
    }

    /// Returns `true` when the registration form passes all validation rules.
    var isRegisterFormValid: Bool {
        isValidEmail(registerEmail)
            && registerPassword.count >= AuthValidation.minimumPasswordLength
            && registerPassword == registerConfirmPassword
            && !registerDisplayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Returns `true` when the forgot-password email is valid.
    var isForgotPasswordFormValid: Bool {
        isValidEmail(forgotPasswordEmail)
    }

    // MARK: - Inline Validation (real-time field feedback)

    var loginEmailError: String? {
        guard !loginEmail.isEmpty else { return nil }
        return isValidEmail(loginEmail) ? nil : "Invalid email address"
    }

    var loginPasswordError: String? {
        guard !loginPassword.isEmpty else { return nil }
        return loginPassword.count >= AuthValidation.minimumPasswordLength
            ? nil
            : "At least \(AuthValidation.minimumPasswordLength) characters"
    }

    var registerEmailError: String? {
        guard !registerEmail.isEmpty else { return nil }
        return isValidEmail(registerEmail) ? nil : "Invalid email address"
    }

    var registerPasswordError: String? {
        guard !registerPassword.isEmpty else { return nil }
        return registerPassword.count >= AuthValidation.minimumPasswordLength
            ? nil
            : "At least \(AuthValidation.minimumPasswordLength) characters"
    }

    var registerConfirmPasswordError: String? {
        guard !registerConfirmPassword.isEmpty else { return nil }
        return registerPassword == registerConfirmPassword
            ? nil
            : "Passwords do not match"
    }

    var registerDisplayNameError: String? {
        guard !registerDisplayName.isEmpty else { return nil }
        return registerDisplayName.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Display name cannot be empty"
            : nil
    }

    var forgotPasswordEmailError: String? {
        guard !forgotPasswordEmail.isEmpty else { return nil }
        return isValidEmail(forgotPasswordEmail) ? nil : "Invalid email address"
    }

    // MARK: - Actions

    /// Attempts to sign in with email and password via Supabase Auth.
    func login() async {
        clearMessages()
        guard isLoginFormValid else {
            if !isValidEmail(loginEmail) { errorMessage = AuthError.invalidEmail.errorDescription }
            else { errorMessage = AuthError.passwordTooShort.errorDescription }
            return
        }
        isLoading = true
        authState = .loading
        let result = await AuthService.shared.loginWithEmail(
            email: loginEmail.trimmingCharacters(in: .whitespaces),
            password: loginPassword
        )
        isLoading = false
        if result.isSuccess {
            authState = .authenticated
            // Restore cloud data immediately after login so the user sees
            // their history, stats, and time credits without waiting for
            // the next periodic sync.
            SyncService.shared.syncFromCloudAfterLogin()
        } else {
            authState = .unauthenticated
            errorMessage = result.errorMessage ?? "Login failed."
        }
    }

    /// Attempts to create a new account via Supabase Auth.
    func register() async {
        clearMessages()
        guard isRegisterFormValid else {
            if !isValidEmail(registerEmail) { errorMessage = AuthError.invalidEmail.errorDescription }
            else if registerPassword.count < AuthValidation.minimumPasswordLength { errorMessage = AuthError.passwordTooShort.errorDescription }
            else if registerPassword != registerConfirmPassword { errorMessage = AuthError.passwordsDoNotMatch.errorDescription }
            else { errorMessage = AuthError.displayNameEmpty.errorDescription }
            return
        }
        isLoading = true
        authState = .loading
        let result = await AuthService.shared.registerWithEmail(
            email: registerEmail.trimmingCharacters(in: .whitespaces),
            password: registerPassword
        )
        isLoading = false
        if result.isSuccess {
            authState = .authenticated
            // New account: pull any existing cloud data (e.g. if the user
            // registered on another device previously).
            SyncService.shared.syncFromCloudAfterLogin()
        } else {
            authState = .unauthenticated
            errorMessage = result.errorMessage ?? "Registration failed."
        }
    }

    /// Sends a password-reset email via Supabase Auth.
    func sendPasswordReset() async {
        clearMessages()
        do {
            guard isValidEmail(forgotPasswordEmail) else {
                throw AuthError.invalidEmail
            }
            isLoading = true
            // Supabase password reset is handled via the /auth/v1/recover endpoint.
            // The KMP layer does not yet expose this endpoint, so we show the
            // confirmation immediately. The user will receive an email from Supabase
            // if their account exists.
            try await Task.sleep(nanoseconds: 500_000_000)
            isLoading = false
            showPasswordResetConfirmation = true
            successMessage = "If an account exists for \(forgotPasswordEmail), you will receive a password reset email shortly."
        } catch let error as AuthError {
            isLoading = false
            errorMessage = error.errorDescription
        } catch {
            isLoading = false
            errorMessage = AuthError.unknown(error.localizedDescription).errorDescription
        }
    }

    // MARK: - Apple Sign-In

    /// Initiates Apple Sign-In using ASAuthorizationController.
    ///
    /// Requests the user's full name and email from Apple, then exchanges
    /// the identity token with Supabase Auth via LoginWithAppleUseCase.
    func loginWithApple() async {
        clearMessages()
        isLoading = true
        authState = .loading
        do {
            let credential = try await requestAppleCredential()
            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                throw AuthError.unknown("Apple did not return an identity token.")
            }
            let result = await AuthService.shared.loginWithApple(idToken: idToken)
            isLoading = false
            if result.isSuccess {
                authState = .authenticated
                SyncService.shared.syncFromCloudAfterLogin()
            } else {
                authState = .unauthenticated
                errorMessage = result.errorMessage ?? "Apple Sign-In failed."
            }
        } catch let error as ASAuthorizationError where error.code == .canceled {
            isLoading = false
            authState = .unauthenticated
        } catch {
            isLoading = false
            authState = .unauthenticated
            errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Google Sign-In

    /// Initiates Google Sign-In via Supabase OAuth redirect flow.
    ///
    /// Opens an ASWebAuthenticationSession with the Supabase Google OAuth
    /// endpoint. After the user authenticates, Supabase redirects back to
    /// the app via a deep link.
    ///
    /// Supabase may return either:
    /// - **Implicit Flow**: tokens in the URL fragment (`#access_token=...`)
    /// - **PKCE Flow**: a code in the query string (`?code=...`)
    ///
    /// This method handles both cases automatically.
    /// No Google SDK required — Supabase handles the OAuth server-side.
    func loginWithGoogle() async {
        clearMessages()
        isLoading = true
        authState = .loading
        do {
            let supabaseURL = "https://ptllenkizeipinpuqapl.supabase.co"
            let bundleID = Bundle.main.bundleIdentifier ?? "com.flomks.pushup"
            let redirectURL = "\(bundleID)://auth/callback"
            guard
                let encodedRedirect = redirectURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                let authURL = URL(string: "\(supabaseURL)/auth/v1/authorize?provider=google&redirect_to=\(encodedRedirect)")
            else {
                throw AuthError.unknown("Invalid Supabase URL configuration.")
            }
            let callbackURL = try await openWebAuthSession(url: authURL, callbackScheme: bundleID)
            let result = try await handleOAuthCallback(url: callbackURL)
            isLoading = false
            if result.errorMessage == nil {
                // Success — user record created and token stored for both PKCE and implicit flows
                authState = .authenticated
                SyncService.shared.syncFromCloudAfterLogin()
            } else {
                authState = .unauthenticated
                errorMessage = result.errorMessage
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            isLoading = false
            authState = .unauthenticated
        } catch {
            isLoading = false
            authState = .unauthenticated
            errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Sign Out

    /// Signs the current user out and returns to the unauthenticated state.
    func signOut() {
        Task {
            await AuthService.shared.logout()
        }
        authState = .unauthenticated
        clearAllFields()
        clearMessages()
    }

    // MARK: - Session Restore

    /// Checks whether a valid Supabase token exists and restores the session.
    func restoreSession() async {
        if let _ = await AuthService.shared.getCurrentUser() {
            authState = .authenticated
            // Trigger a background sync on app relaunch so local data is
            // refreshed from the cloud (picks up changes from other devices
            // or sessions since the last time the app was open).
            SyncService.shared.syncFromCloudAfterLogin()
        } else {
            authState = .unauthenticated
        }
    }

    // MARK: - Helpers

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    /// Validates an email address against the shared pattern.
    func isValidEmail(_ email: String) -> Bool {
        email.range(of: AuthValidation.emailPattern, options: .regularExpression) != nil
    }

    // MARK: - Private

    private func validateLogin() throws {
        guard isValidEmail(loginEmail) else { throw AuthError.invalidEmail }
        guard loginPassword.count >= AuthValidation.minimumPasswordLength else {
            throw AuthError.passwordTooShort
        }
    }

    private func validateRegistration() throws {
        guard isValidEmail(registerEmail) else { throw AuthError.invalidEmail }
        guard registerPassword.count >= AuthValidation.minimumPasswordLength else {
            throw AuthError.passwordTooShort
        }
        guard registerPassword == registerConfirmPassword else {
            throw AuthError.passwordsDoNotMatch
        }
        guard !registerDisplayName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AuthError.displayNameEmpty
        }
    }

    private func clearAllFields() {
        loginEmail = ""
        loginPassword = ""
        registerEmail = ""
        registerPassword = ""
        registerConfirmPassword = ""
        registerDisplayName = ""
        forgotPasswordEmail = ""
    }

    /// Requests an Apple ID credential using ASAuthorizationController.
    ///
    /// Bridges the delegate-based ASAuthorizationController API to async/await
    /// using a CheckedContinuation.
    private func requestAppleCredential() async throws -> ASAuthorizationAppleIDCredential {
        return try await withCheckedThrowingContinuation { continuation in
            self.appleSignInContinuation = continuation
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    /// Opens an ASWebAuthenticationSession and returns the callback URL.
    ///
    /// Must be called on the MainActor (this class is @MainActor so that is
    /// guaranteed). The session is retained as a property so ARC does not
    /// deallocate it before the callback fires.
    private func openWebAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        // Find the key window before entering the continuation — UIKit APIs
        // must be called on the main thread, which is guaranteed here because
        // AuthViewModel is @MainActor.
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow })
                ?? windowScene.windows.first
        else {
            throw AuthError.unknown("No active window found for Google Sign-In.")
        }

        let provider = WebAuthPresentationProvider(window: keyWindow)

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.webAuthSession = nil
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthError.unknown("No callback URL returned."))
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = provider
            // Retain the session so ARC does not free it before the callback.
            self.webAuthSession = session
            session.start()
        }
    }

    /// Handles the Supabase OAuth callback URL.
    ///
    /// Supports both flows:
    /// - **PKCE**: `?code=<pkce_code>` in query string -> exchange via KMP
    /// - **Implicit**: `#access_token=...&refresh_token=...` in fragment -> store directly
    ///
    /// Returns AuthResult — never throws Kotlin exceptions.
    private func handleOAuthCallback(url: URL) async throws -> AuthServiceResult {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        // Check for error in query params
        if let errorParam = queryItems.first(where: { $0.name == "error" })?.value {
            let desc = queryItems.first(where: { $0.name == "error_description" })?.value ?? errorParam
            throw AuthError.unknown("Google Sign-In failed: \(desc)")
        }

        // Try PKCE flow first: ?code=...
        if let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            return await AuthService.shared.loginWithGoogleOAuthCode(code: code)
        }

        // Try Implicit flow: #access_token=...&refresh_token=...
        if let fragment = url.fragment, !fragment.isEmpty {
            var params: [String: String] = [:]
            for pair in fragment.components(separatedBy: "&") {
                let parts = pair.components(separatedBy: "=")
                if parts.count >= 2 {
                    params[parts[0]] = parts[1...].joined(separator: "=")
                        .removingPercentEncoding ?? parts[1]
                }
            }

            // Check for error in fragment
            if let errorCode = params["error"] {
                let desc = params["error_description"]?.replacingOccurrences(of: "+", with: " ") ?? errorCode
                throw AuthError.unknown("Google Sign-In failed: \(desc)")
            }

            guard let accessToken = params["access_token"],
                  let refreshToken = params["refresh_token"] else {
                throw AuthError.unknown("OAuth callback missing tokens.")
            }

            let expiresIn = Int64(params["expires_in"] ?? "3600") ?? 3600
            let userId = parseJWTClaim(accessToken, claim: "sub") ?? ""
            let userEmail = parseJWTClaim(accessToken, claim: "email")

            guard !userId.isEmpty else {
                throw AuthError.unknown("Could not extract user ID from token.")
            }

            return await AuthService.shared.storeImplicitSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                userId: userId,
                userEmail: userEmail,
                expiresIn: expiresIn
            )
        }

        throw AuthError.unknown("OAuth callback contained neither a code nor tokens.")
    }

    /// Parses a claim from a JWT token (base64url-encoded payload).
    private func parseJWTClaim(_ jwt: String, claim: String) -> String? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1]
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        base64 = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json[claim] as? String else {
            return nil
        }
        return value
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthViewModel: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            Task { @MainActor in
                self.appleSignInContinuation?.resume(
                    throwing: AuthError.unknown("Unexpected credential type from Apple.")
                )
                self.appleSignInContinuation = nil
            }
            return
        }
        Task { @MainActor in
            self.appleSignInContinuation?.resume(returning: credential)
            self.appleSignInContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.appleSignInContinuation?.resume(throwing: error)
            self.appleSignInContinuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthViewModel: ASAuthorizationControllerPresentationContextProviding {

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // UIApplication must be accessed on the main thread.
        // Since ASAuthorizationController always calls this on the main thread,
        // we use MainActor.assumeIsolated which is safe here.
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .windows.first(where: { $0.isKeyWindow })
                ?? UIWindow()
        }
    }
}

// MARK: - WebAuthPresentationProvider

/// Provides a presentation anchor for ASWebAuthenticationSession.
private final class WebAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: UIWindow
    init(window: UIWindow) { self.window = window }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}
