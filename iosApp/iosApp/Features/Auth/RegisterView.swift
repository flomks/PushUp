import AuthenticationServices
import SwiftUI

// MARK: - RegisterView

/// Registration screen with email, password, confirm password, and display name.
///
/// Validates all fields inline and shows a loading state during the API call.
/// On success, `AuthViewModel.authState` transitions to `.authenticated`,
/// which the root view observes to navigate to `MainTabView`.
struct RegisterView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showPassword: Bool = false
    @State private var showConfirmPassword: Bool = false
    @FocusState private var focusedField: RegisterField?

    private enum RegisterField: Hashable {
        case displayName, email, password, confirmPassword
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                headerSection
                    .padding(.top, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.xl)

                // Quick sign-up with Apple (above the form for discoverability)
                quickSignUpSection
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.bottom, AppSpacing.lg)

                // Form
                formCard
                    .padding(.horizontal, AppSpacing.screenHorizontal)

                // Terms note
                termsNote
                    .padding(.top, AppSpacing.lg)
                    .padding(.horizontal, AppSpacing.screenHorizontal)

                // Already have account
                loginLink
                    .padding(.top, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.screenVerticalBottom)
            }
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearMessages() } }
        )) {
            Button("OK") { viewModel.clearMessages() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.secondary, AppColors.secondary.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(icon: .personBadgePlus)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .shadow(color: AppColors.secondary.opacity(0.3), radius: 12, x: 0, y: 6)

            VStack(spacing: AppSpacing.xxs) {
                Text("New Account")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Create your PushUp account and get started")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
    }

    // MARK: - Quick Sign-Up Section

    /// Shows the Apple Sign-In button above the email form so users can
    /// register with one tap instead of filling out the full form.
    private var quickSignUpSection: some View {
        VStack(spacing: AppSpacing.sm) {
            // Apple Sign-In -- official button required by App Store Guidelines
            AppleSignInButton {
                Task { await viewModel.loginWithApple() }
            }
            .disabled(viewModel.isLoading)
            .opacity(viewModel.isLoading ? 0.6 : 1.0)

            // Divider
            HStack(spacing: AppSpacing.md) {
                Rectangle()
                    .fill(AppColors.separator)
                    .frame(height: 1)
                Text("or register with email")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize()
                Rectangle()
                    .fill(AppColors.separator)
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Form Card

    private var formCard: some View {
        Card(hasShadow: true) {
            VStack(spacing: AppSpacing.md) {

                // Display name
                AuthTextField(
                    title: "Display Name",
                    placeholder: "What should we call you?",
                    text: $viewModel.registerDisplayName,
                    textContentType: .name,
                    errorMessage: viewModel.registerDisplayNameError,
                    icon: .person,
                    autocapitalization: .words
                )
                .focused($focusedField, equals: .displayName)
                .submitLabel(.next)
                .onSubmit { focusedField = .email }

                // Email
                AuthTextField(
                    title: "Email",
                    placeholder: "name@example.com",
                    text: $viewModel.registerEmail,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress,
                    errorMessage: viewModel.registerEmailError,
                    icon: .envelope
                )
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }

                // Password
                AuthSecureField(
                    title: "Password",
                    placeholder: "At least 8 characters",
                    text: $viewModel.registerPassword,
                    showPassword: $showPassword,
                    errorMessage: viewModel.registerPasswordError
                )
                .focused($focusedField, equals: .password)
                .submitLabel(.next)
                .onSubmit { focusedField = .confirmPassword }

                // Confirm password
                AuthSecureField(
                    title: "Confirm Password",
                    placeholder: "Repeat password",
                    text: $viewModel.registerConfirmPassword,
                    showPassword: $showConfirmPassword,
                    errorMessage: viewModel.registerConfirmPasswordError
                )
                .focused($focusedField, equals: .confirmPassword)
                .submitLabel(.go)
                .onSubmit {
                    focusedField = nil
                    Task { await viewModel.register() }
                }

                // Password strength indicator
                if !viewModel.registerPassword.isEmpty {
                    passwordStrengthView
                }

                // Register button
                PrimaryButton(
                    "Create Account",
                    icon: .checkmark,
                    isLoading: viewModel.isLoading
                ) {
                    focusedField = nil
                    Task { await viewModel.register() }
                }
                .disabled(!viewModel.isRegisterFormValid || viewModel.isLoading)
                .padding(.top, AppSpacing.xs)
            }
        }
    }

    // MARK: - Password Strength

    private var passwordStrengthView: some View {
        let strength = passwordStrength(viewModel.registerPassword)
        return VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(spacing: AppSpacing.xxs) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < strength.score ? strength.color : AppColors.separator)
                        .frame(height: 4)
                }
            }

            Text(strength.label)
                .font(AppTypography.caption1)
                .foregroundStyle(strength.color)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.registerPassword)
    }

    // MARK: - Terms Note

    private var termsNote: some View {
        Text("By registering you agree to our Terms of Service and Privacy Policy.")
            .font(AppTypography.caption1)
            .foregroundStyle(AppColors.textTertiary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Login Link

    private var loginLink: some View {
        HStack(spacing: AppSpacing.xxs) {
            Text("Already have an account?")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)

            Button("Sign In") {
                dismiss()
            }
            .font(AppTypography.subheadlineSemibold)
            .foregroundStyle(AppColors.primary)
        }
    }

    // MARK: - Helpers

    private struct PasswordStrength {
        let score: Int   // 0-4
        let label: String
        let color: Color
    }

    private func passwordStrength(_ password: String) -> PasswordStrength {
        var score = 0
        if password.count >= 8  { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.range(of: "[A-Z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[0-9!@#$%^&*]", options: .regularExpression) != nil { score += 1 }

        switch score {
        case 0, 1:
            return PasswordStrength(score: 1, label: "Weak", color: AppColors.error)
        case 2:
            return PasswordStrength(score: 2, label: "Fair", color: AppColors.warning)
        case 3:
            return PasswordStrength(score: 3, label: "Strong", color: AppColors.success.opacity(0.7))
        default:
            return PasswordStrength(score: 4, label: "Very strong", color: AppColors.success)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Register") {
    NavigationStack {
        RegisterView(viewModel: AuthViewModel())
    }
}
#endif
