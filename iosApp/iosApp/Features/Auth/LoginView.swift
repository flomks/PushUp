import SwiftUI

// MARK: - LoginView

/// Login screen with email/password, Apple Sign-In, and Google Sign-In.
///
/// Observes `AuthViewModel` for loading states, validation errors, and
/// the authenticated state that triggers navigation to `MainTabView`.
struct LoginView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: AuthViewModel

    @State private var showPassword: Bool = false
    @State private var showForgotPassword: Bool = false
    @State private var showRegister: Bool = false
    @FocusState private var focusedField: LoginField?

    private enum LoginField: Hashable {
        case email, password
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero section
                    heroSection
                        .padding(.top, AppSpacing.xxl)
                        .padding(.bottom, AppSpacing.xl)

                    // Form card
                    formCard
                        .padding(.horizontal, AppSpacing.screenHorizontal)

                    // Divider with "oder"
                    orDivider
                        .padding(.vertical, AppSpacing.lg)
                        .padding(.horizontal, AppSpacing.screenHorizontal)

                    // Social sign-in buttons
                    socialButtons
                        .padding(.horizontal, AppSpacing.screenHorizontal)

                    // Register link
                    registerLink
                        .padding(.top, AppSpacing.xl)
                        .padding(.bottom, AppSpacing.screenVerticalBottom)
                }
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(isPresented: $showForgotPassword) {
                ForgotPasswordView(viewModel: viewModel)
            }
            .navigationDestination(isPresented: $showRegister) {
                RegisterView(viewModel: viewModel)
            }
            .alert("Fehler", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearMessages() } }
            )) {
                Button("OK") { viewModel.clearMessages() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: AppSpacing.md) {
            // App icon / logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.primary, AppColors.primary.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)

                Image(icon: .figureStrengthTraining)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .shadow(color: AppColors.primary.opacity(0.3), radius: 16, x: 0, y: 8)

            VStack(spacing: AppSpacing.xs) {
                Text("Willkommen zurueck")
                    .font(AppTypography.title1)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Melde dich an und verdiene Zeitguthaben")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
    }

    // MARK: - Form Card

    private var formCard: some View {
        Card(hasShadow: true) {
            VStack(spacing: AppSpacing.md) {
                // Email field
                AuthTextField(
                    title: "E-Mail",
                    placeholder: "name@beispiel.de",
                    text: $viewModel.loginEmail,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress,
                    errorMessage: viewModel.loginEmailError,
                    icon: .envelope
                )
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }

                // Password field
                AuthSecureField(
                    title: "Passwort",
                    placeholder: "Mindestens 8 Zeichen",
                    text: $viewModel.loginPassword,
                    showPassword: $showPassword,
                    errorMessage: viewModel.loginPasswordError
                )
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit {
                    focusedField = nil
                    Task { await viewModel.login() }
                }

                // Forgot password link
                HStack {
                    Spacer()
                    Button("Passwort vergessen?") {
                        showForgotPassword = true
                    }
                    .font(AppTypography.buttonSecondary)
                    .foregroundStyle(AppColors.primary)
                }
                .padding(.top, -AppSpacing.xs)

                // Login button
                PrimaryButton(
                    "Anmelden",
                    icon: .arrowRight,
                    isLoading: viewModel.isLoading
                ) {
                    focusedField = nil
                    Task { await viewModel.login() }
                }
                .disabled(!viewModel.isLoginFormValid || viewModel.isLoading)
                .padding(.top, AppSpacing.xs)
            }
        }
    }

    // MARK: - Or Divider

    private var orDivider: some View {
        HStack(spacing: AppSpacing.md) {
            Rectangle()
                .fill(AppColors.separator)
                .frame(height: 1)

            Text("oder")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
                .fixedSize()

            Rectangle()
                .fill(AppColors.separator)
                .frame(height: 1)
        }
    }

    // MARK: - Social Buttons

    private var socialButtons: some View {
        VStack(spacing: AppSpacing.sm) {
            // Apple Sign-In
            SocialSignInButton(
                title: "Mit Apple anmelden",
                icon: .appleLogo,
                backgroundColor: AppColors.textPrimary,
                foregroundColor: AppColors.backgroundPrimary
            ) {
                // Apple Sign-In integration point
                // In production: use ASAuthorizationAppleIDProvider
            }

            // Google Sign-In
            SocialSignInButton(
                title: "Mit Google anmelden",
                icon: .globe,
                backgroundColor: AppColors.backgroundSecondary,
                foregroundColor: AppColors.textPrimary,
                hasBorder: true
            ) {
                // Google Sign-In integration point
                // In production: use GoogleSignIn SDK
            }
        }
    }

    // MARK: - Register Link

    private var registerLink: some View {
        HStack(spacing: AppSpacing.xxs) {
            Text("Noch kein Konto?")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)

            Button("Registrieren") {
                showRegister = true
            }
            .font(AppTypography.subheadlineSemibold)
            .foregroundStyle(AppColors.primary)
        }
    }
}

// MARK: - SocialSignInButton

/// A full-width button styled for social sign-in providers (Apple, Google).
struct SocialSignInButton: View {

    let title: String
    let icon: AppIcon
    let backgroundColor: Color
    let foregroundColor: Color
    var hasBorder: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                Image(icon: icon)
                    .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))

                Text(title)
                    .font(AppTypography.buttonPrimary)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.buttonHeightPrimary)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
            .overlay(
                Group {
                    if hasBorder {
                        RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                            .strokeBorder(AppColors.separator, lineWidth: 1.5)
                    }
                }
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - AuthTextField

/// A labeled text field with an optional leading icon and inline error message.
struct AuthTextField: View {

    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var errorMessage: String? = nil
    var icon: AppIcon? = nil
    var autocapitalization: TextInputAutocapitalization = .never

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(title)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textSecondary)

            HStack(spacing: AppSpacing.xs) {
                if let icon {
                    Image(icon: icon)
                        .font(.system(size: AppSpacing.iconSizeSmall, weight: .medium))
                        .foregroundStyle(
                            errorMessage != nil ? AppColors.error : AppColors.textTertiary
                        )
                        .frame(width: AppSpacing.iconSizeStandard)
                }

                TextField(placeholder, text: $text)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(autocapitalization)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(height: AppSpacing.buttonHeightPrimary)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                    .strokeBorder(
                        errorMessage != nil ? AppColors.error : Color.clear,
                        lineWidth: 1.5
                    )
            )

            if let errorMessage {
                Label(errorMessage, systemImage: AppIcon.exclamationmarkCircleFill.rawValue)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.error)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }
}

// MARK: - AuthSecureField

/// A labeled secure text field with a show/hide password toggle.
struct AuthSecureField: View {

    let title: String
    let placeholder: String
    @Binding var text: String
    @Binding var showPassword: Bool
    var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(title)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textSecondary)

            HStack(spacing: AppSpacing.xs) {
                Image(icon: .lock)
                    .font(.system(size: AppSpacing.iconSizeSmall, weight: .medium))
                    .foregroundStyle(
                        errorMessage != nil ? AppColors.error : AppColors.textTertiary
                    )
                    .frame(width: AppSpacing.iconSizeStandard)

                Group {
                    if showPassword {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Button {
                    showPassword.toggle()
                } label: {
                    Image(icon: showPassword ? .eyeSlash : .eye)
                        .font(.system(size: AppSpacing.iconSizeSmall, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showPassword ? "Passwort verbergen" : "Passwort anzeigen")
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(height: AppSpacing.buttonHeightPrimary)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                    .strokeBorder(
                        errorMessage != nil ? AppColors.error : Color.clear,
                        lineWidth: 1.5
                    )
            )

            if let errorMessage {
                Label(errorMessage, systemImage: AppIcon.exclamationmarkCircleFill.rawValue)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.error)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Login") {
    LoginView(viewModel: AuthViewModel())
}
#endif
