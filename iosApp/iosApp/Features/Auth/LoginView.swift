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
                Task { await viewModel.loginWithApple() }
            }
            .disabled(viewModel.isLoading)

            // Google Sign-In
            SocialSignInButton(
                title: "Mit Google anmelden",
                icon: .globe,
                backgroundColor: AppColors.backgroundSecondary,
                foregroundColor: AppColors.textPrimary,
                hasBorder: true
            ) {
                Task { await viewModel.loginWithGoogle() }
            }
            .disabled(viewModel.isLoading)
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

// MARK: - Preview

#if DEBUG
#Preview("Login") {
    LoginView(viewModel: AuthViewModel())
}
#endif
