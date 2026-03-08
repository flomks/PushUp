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
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Bitte gib eine gueltige E-Mail-Adresse ein."
        case .passwordTooShort:
            return "Das Passwort muss mindestens 8 Zeichen lang sein."
        case .passwordsDoNotMatch:
            return "Die Passwoerter stimmen nicht ueberein."
        case .displayNameEmpty:
            return "Bitte gib einen Anzeigenamen ein."
        case .networkError(let msg):
            return "Netzwerkfehler: \(msg)"
        case .invalidCredentials:
            return "E-Mail oder Passwort ist falsch."
        case .emailAlreadyInUse:
            return "Diese E-Mail-Adresse wird bereits verwendet."
        case .unknown(let msg):
            return "Ein Fehler ist aufgetreten: \(msg)"
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
/// and password-reset flows.
///
/// All published properties are updated on the main actor.
/// API calls are simulated with async/await delays to demonstrate
/// loading states; replace the stub implementations with real
/// network calls when the backend is wired up.
@MainActor
final class AuthViewModel: ObservableObject {

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
        return isValidEmail(loginEmail) ? nil : "Ungueltige E-Mail-Adresse"
    }

    var loginPasswordError: String? {
        guard !loginPassword.isEmpty else { return nil }
        return loginPassword.count >= AuthValidation.minimumPasswordLength
            ? nil
            : "Mindestens \(AuthValidation.minimumPasswordLength) Zeichen"
    }

    var registerEmailError: String? {
        guard !registerEmail.isEmpty else { return nil }
        return isValidEmail(registerEmail) ? nil : "Ungueltige E-Mail-Adresse"
    }

    var registerPasswordError: String? {
        guard !registerPassword.isEmpty else { return nil }
        return registerPassword.count >= AuthValidation.minimumPasswordLength
            ? nil
            : "Mindestens \(AuthValidation.minimumPasswordLength) Zeichen"
    }

    var registerConfirmPasswordError: String? {
        guard !registerConfirmPassword.isEmpty else { return nil }
        return registerPassword == registerConfirmPassword
            ? nil
            : "Passwoerter stimmen nicht ueberein"
    }

    var registerDisplayNameError: String? {
        guard !registerDisplayName.isEmpty else { return nil }
        return registerDisplayName.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Anzeigename darf nicht leer sein"
            : nil
    }

    var forgotPasswordEmailError: String? {
        guard !forgotPasswordEmail.isEmpty else { return nil }
        return isValidEmail(forgotPasswordEmail) ? nil : "Ungueltige E-Mail-Adresse"
    }

    // MARK: - Actions

    /// Attempts to sign in with email and password.
    func login() async {
        clearMessages()
        do {
            try validateLogin()
            isLoading = true
            authState = .loading
            // Simulate network call -- replace with real auth service call
            try await Task.sleep(nanoseconds: 1_500_000_000)
            isLoading = false
            authState = .authenticated
        } catch let error as AuthError {
            isLoading = false
            authState = .unauthenticated
            errorMessage = error.errorDescription
        } catch {
            isLoading = false
            authState = .unauthenticated
            errorMessage = AuthError.unknown(error.localizedDescription).errorDescription
        }
    }

    /// Attempts to create a new account.
    func register() async {
        clearMessages()
        do {
            try validateRegistration()
            isLoading = true
            authState = .loading
            // Simulate network call
            try await Task.sleep(nanoseconds: 1_800_000_000)
            isLoading = false
            authState = .authenticated
        } catch let error as AuthError {
            isLoading = false
            authState = .unauthenticated
            errorMessage = error.errorDescription
        } catch {
            isLoading = false
            authState = .unauthenticated
            errorMessage = AuthError.unknown(error.localizedDescription).errorDescription
        }
    }

    /// Sends a password-reset email.
    func sendPasswordReset() async {
        clearMessages()
        do {
            guard isValidEmail(forgotPasswordEmail) else {
                throw AuthError.invalidEmail
            }
            isLoading = true
            // Simulate network call
            try await Task.sleep(nanoseconds: 1_200_000_000)
            isLoading = false
            showPasswordResetConfirmation = true
            successMessage = "Wir haben dir eine E-Mail mit einem Link zum Zuruecksetzen deines Passworts gesendet."
        } catch let error as AuthError {
            isLoading = false
            errorMessage = error.errorDescription
        } catch {
            isLoading = false
            errorMessage = AuthError.unknown(error.localizedDescription).errorDescription
        }
    }

    /// Initiates Google Sign-In.
    ///
    /// Replace the simulated delay with a real `GoogleSignIn` SDK call once
    /// the OAuth client ID is configured in `Info.plist`.
    func loginWithGoogle() async {
        clearMessages()
        isLoading = true
        authState = .loading
        do {
            // TODO: Replace with real GoogleSignIn SDK call:
            // let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            // let idToken = result.user.idToken?.tokenString ?? ""
            // ... exchange idToken with backend
            try await Task.sleep(nanoseconds: 1_500_000_000)
            isLoading = false
            authState = .authenticated
        } catch {
            isLoading = false
            authState = .unauthenticated
            errorMessage = AuthError.networkError(error.localizedDescription).errorDescription
        }
    }

    /// Initiates Apple Sign-In.
    ///
    /// Replace the simulated delay with a real `ASAuthorizationAppleIDProvider`
    /// request once the "Sign in with Apple" capability is enabled in Xcode.
    func loginWithApple() async {
        clearMessages()
        isLoading = true
        authState = .loading
        do {
            // TODO: Replace with real Apple Sign-In:
            // let provider = ASAuthorizationAppleIDProvider()
            // let request  = provider.createRequest()
            // request.requestedScopes = [.fullName, .email]
            // let result = try await ASAuthorizationController(authorizationRequests: [request]).performRequests()
            // ... exchange credential with backend
            try await Task.sleep(nanoseconds: 1_500_000_000)
            isLoading = false
            authState = .authenticated
        } catch {
            isLoading = false
            authState = .unauthenticated
            errorMessage = AuthError.networkError(error.localizedDescription).errorDescription
        }
    }

    /// Signs the current user out and returns to the unauthenticated state.
    func signOut() {
        authState = .unauthenticated
        clearAllFields()
        clearMessages()
    }

    // MARK: - Helpers

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    /// Validates an email address against the shared pattern.
    /// Exposed for use by views that need inline validation without
    /// duplicating the regex.
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
}
