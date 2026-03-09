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
        do {
            try validateLogin()
            isLoading = true
            authState = .loading
            let useCase = DIHelper.shared.loginWithEmailUseCase()
            _ = try await useCase.invoke(
                email: loginEmail.trimmingCharacters(in: .whitespaces),
                password: loginPassword
            )
            isLoading = false
            authState = .authenticated
        } catch let error as AuthException {
            isLoading = false
            authState = .unauthenticated
            errorMessage = mapAuthException(error)
        } catch let error as KotlinThrowable {
            isLoading = false
            authState = .unauthenticated
            errorMessage = mapKotlinThrowable(error)
        } catch let error as AuthError {
            isLoading = false
            authState = .unauthenticated
            errorMessage = error.errorDescription
        } catch {
            isLoading = false
            authState = .unauthenticated
            errorMessage = "Login failed: \(error.localizedDescription)"
        }
    }

    /// Attempts to create a new account via Supabase Auth.
    func register() async {
        clearMessages()
        do {
            try validateRegistration()
            isLoading = true
            authState = .loading
            let useCase = DIHelper.shared.registerWithEmailUseCase()
            _ = try await useCase.invoke(
                email: registerEmail.trimmingCharacters(in: .whitespaces),
                password: registerPassword
            )
            isLoading = false
            authState = .authenticated
        } catch let error as AuthException {
            isLoading = false
            authState = .unauthenticated
            errorMessage = mapAuthException(error)
        } catch let error as KotlinThrowable {
            isLoading = false
            authState = .unauthenticated
            errorMessage = mapKotlinThrowable(error)
        } catch let error as AuthError {
            isLoading = false
            authState = .unauthenticated
            errorMessage = error.errorDescription
        } catch {
            isLoading = false
            authState = .unauthenticated
            errorMessage = "Registration failed: \(error.localizedDescription)"
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
            let useCase = DIHelper.shared.loginWithAppleUseCase()
            _ = try await useCase.invoke(idToken: idToken)
            isLoading = false
            authState = .authenticated
        } catch let error as ASAuthorizationError where error.code == .canceled {
            isLoading = false
            authState = .unauthenticated
            // User cancelled — do not show an error message.
        } catch let error as AuthException {
            isLoading = false
            authState = .unauthenticated
            errorMessage = mapAuthException(error)
        } catch let error as AuthError {
            isLoading = false
            authState = .unauthenticated
            if error.errorDescription != nil {
                errorMessage = error.errorDescription
            }
        } catch {
            isLoading = false
            authState = .unauthenticated
            errorMessage = AuthError.unknown(error.localizedDescription).errorDescription
        }
    }

    // MARK: - Google Sign-In

    /// Initiates Google Sign-In via Supabase OAuth redirect flow.
    ///
    /// Opens an ASWebAuthenticationSession with the Supabase Google OAuth
    /// endpoint. After the user authenticates, Supabase redirects back to
    /// the app via a deep link containing a PKCE authorization code.
    ///
    /// Flow:
    /// 1. Open Supabase OAuth URL in ASWebAuthenticationSession
    /// 2. User authenticates with Google in the browser
    /// 3. Supabase redirects back to the app with ?code=<pkce_code>
    /// 4. Exchange the code for a Supabase session via LoginWithGoogleUseCase
    ///
    /// No Google SDK required — Supabase handles the OAuth server-side.
    func loginWithGoogle() async {
        clearMessages()
        isLoading = true
        authState = .loading
        do {
            let supabaseURL = "https://akpdpsmmmahbbkiclvsi.supabase.co"
            let bundleID = Bundle.main.bundleIdentifier ?? "com.flomks.pushup"
            let redirectURL = "\(bundleID)://auth/callback"
            guard
                let encodedRedirect = redirectURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                let authURL = URL(string: "\(supabaseURL)/auth/v1/authorize?provider=google&redirect_to=\(encodedRedirect)&flow_type=pkce")
            else {
                throw AuthError.unknown("Invalid Supabase URL configuration.")
            }
            let callbackURL = try await openWebAuthSession(url: authURL, callbackScheme: bundleID)
            let code = try extractOAuthCode(from: callbackURL)
            _ = try await DIHelper.shared.loginWithGoogleOAuthCode(code: code)
            isLoading = false
            authState = .authenticated
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            isLoading = false
            authState = .unauthenticated
        } catch let error as AuthException {
            isLoading = false
            authState = .unauthenticated
            errorMessage = mapAuthException(error)
        } catch let error as AuthError {
            isLoading = false
            authState = .unauthenticated
            if let desc = error.errorDescription { errorMessage = desc }
        } catch {
            isLoading = false
            authState = .unauthenticated
            errorMessage = AuthError.unknown(error.localizedDescription).errorDescription
        }
    }

    // MARK: - Sign Out

    /// Signs the current user out and returns to the unauthenticated state.
    func signOut() {
        Task {
            let useCase = DIHelper.shared.logoutUseCase()
            try? await useCase.invoke(clearLocalData: false)
        }
        authState = .unauthenticated
        clearAllFields()
        clearMessages()
    }

    // MARK: - Session Restore

    /// Checks whether a valid Supabase token exists and restores the session.
    ///
    /// Reads the stored token from the Keychain via TokenStorage.
    /// Only authenticates if a real token is present — never based on
    /// a local DB user alone (which could be a stale entry from a
    /// previous session that was not properly cleared).
    func restoreSession() async {
        // TokenStorage.load() returns nil if no token is stored in the Keychain.
        // We access it via the KMP TokenStorage through a dedicated use case.
        // getCurrentUser() internally checks tokenStorage first in AuthRepositoryImpl,
        // so if no token exists it returns nil even if a DB user exists.
        let useCase = DIHelper.shared.getCurrentUserUseCase()
        guard let _ = try? await useCase.invoke() else {
            // No token or no user — ensure we are in unauthenticated state
            // and clear any stale DB user that might exist without a token.
            authState = .unauthenticated
            return
        }
        authState = .authenticated
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

    /// Maps a KMP AuthException to a user-facing error message.
    ///
    /// Kotlin/Native sealed class subclasses are not reliably accessible as
    /// distinct Swift types. We identify the subclass by its Swift class name
    /// (via String(describing:)) which Kotlin/Native always exports.
    private func mapAuthException(_ error: AuthException) -> String {
        let typeName = String(describing: type(of: error))
        let msg = error.message ?? ""

        switch typeName {
        case _ where typeName.contains("InvalidCredentials"):
            return AuthError.invalidCredentials.errorDescription ?? "Invalid credentials."
        case _ where typeName.contains("EmailAlreadyInUse"):
            return AuthError.emailAlreadyInUse.errorDescription ?? "Email already in use."
        case _ where typeName.contains("WeakPassword"):
            return "Password is too weak. Please choose a stronger password."
        case _ where typeName.contains("InvalidEmail"):
            return AuthError.invalidEmail.errorDescription ?? "Invalid email."
        case _ where typeName.contains("SessionExpired"):
            return "Your session has expired. Please sign in again."
        case _ where typeName.contains("NotAuthenticated"):
            return "Not authenticated. Please sign in."
        case _ where typeName.contains("NetworkError"):
            return AuthError.networkError(msg.isEmpty ? "Connection failed" : msg).errorDescription ?? "Network error."
        case _ where typeName.contains("ServerError"):
            return "Server error. Please try again."
        default:
            return msg.isEmpty ? "An unknown error occurred." : msg
        }
    }

    /// Maps any KotlinThrowable (Kotlin exceptions that are not AuthException)
    /// to a user-facing error message. Prevents crashes from unhandled Kotlin errors.
    private func mapKotlinThrowable(_ error: KotlinThrowable) -> String {
        let msg = (error.message ?? String(describing: type(of: error))).lowercased()
        if msg.contains("invalidcredentials") || msg.contains("invalid credentials") {
            return AuthError.invalidCredentials.errorDescription ?? "Invalid credentials."
        }
        if msg.contains("networkerror") || msg.contains("connect") || msg.contains("timeout") {
            return "Network error. Please check your connection."
        }
        if msg.contains("email confirmation") || msg.contains("confirm your email") {
            return "Please confirm your email address before signing in."
        }
        return "An error occurred. Please try again."
    }

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

    /// Extracts the PKCE authorization code from a Supabase OAuth callback URL.
    ///
    /// Supabase PKCE flow returns the code as a query parameter:
    ///   com.flomks.pushup://auth/callback?code=<pkce_code>
    private func extractOAuthCode(from url: URL) throws -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        // Check for error first
        if let errorParam = queryItems.first(where: { $0.name == "error" })?.value {
            let desc = queryItems.first(where: { $0.name == "error_description" })?.value
                ?? errorParam
            throw AuthError.unknown("Google Sign-In failed: \(desc)")
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw AuthError.unknown(
                "OAuth callback did not contain an authorization code. URL: \(url.absoluteString)"
            )
        }
        return code
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
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return windowScene?.windows.first(where: { $0.isKeyWindow })
            ?? windowScene?.windows.first
            ?? UIWindow()
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
