import AuthenticationServices
import SwiftUI

// MARK: - LoginView

/// Social-only sign-in screen.
///
/// Shows Apple Sign-In and Google Sign-In buttons. Email/password and
/// registration flows are kept in the codebase but not exposed in the UI.
struct LoginView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: AuthViewModel

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    AppColors.backgroundPrimary,
                    AppColors.backgroundSecondary,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Hero
                heroSection

                Spacer()
                Spacer()

                // Sign-in buttons
                signInSection
                    .padding(.horizontal, AppSpacing.xl)

                // Legal note
                legalNote
                    .padding(.top, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.screenVerticalBottom)
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearMessages() } }
        )) {
            Button("OK") { viewModel.clearMessages() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: AppSpacing.lg) {
            // App logo
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            VStack(spacing: AppSpacing.xs) {
                Text("Sinura")
                    .font(AppTypography.title1)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Earn your screen time")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
    }

    // MARK: - Sign-In Section

    private var signInSection: some View {
        VStack(spacing: AppSpacing.sm) {
            // Section label
            Text("Continue with")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, AppSpacing.xxs)

            // Apple Sign-In -- official button required by App Store Guidelines (4.8)
            AppleSignInButton {
                Task { await viewModel.loginWithApple() }
            }
            .disabled(viewModel.isLoading)
            .opacity(viewModel.isLoading ? 0.6 : 1.0)

            // Google Sign-In
            SocialSignInButton(
                title: "Continue with Google",
                icon: .globe,
                backgroundColor: AppColors.backgroundSecondary,
                foregroundColor: AppColors.textPrimary,
                hasBorder: true
            ) {
                Task { await viewModel.loginWithGoogle() }
            }
            .disabled(viewModel.isLoading)
            .opacity(viewModel.isLoading ? 0.6 : 1.0)

            // Loading indicator shown while auth is in progress
            if viewModel.isLoading {
                HStack(spacing: AppSpacing.xs) {
                    ProgressView()
                        .tint(AppColors.textSecondary)
                    Text("Signing in...")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.top, AppSpacing.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
    }

    // MARK: - Legal Note

    private var legalNote: some View {
        Text("By continuing you agree to our Terms of Service and Privacy Policy.")
            .font(AppTypography.caption2)
            .foregroundStyle(AppColors.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.xl)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Login") {
    LoginView(viewModel: AuthViewModel())
}

#Preview("Login - Dark") {
    LoginView(viewModel: AuthViewModel())
        .preferredColorScheme(.dark)
}
#endif
