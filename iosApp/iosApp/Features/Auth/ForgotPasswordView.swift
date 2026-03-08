import SwiftUI

// MARK: - ForgotPasswordView

/// Password-reset screen. The user enters their email address and receives
/// a reset link. Shows a confirmation state after the request succeeds.
struct ForgotPasswordView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @FocusState private var emailFocused: Bool

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.showPasswordResetConfirmation {
                    confirmationView
                        .padding(.top, AppSpacing.xxl)
                } else {
                    requestView
                        .padding(.top, AppSpacing.xl)
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.bottom, AppSpacing.screenVerticalBottom)
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Passwort zuruecksetzen")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Reset confirmation state when leaving the screen
            viewModel.showPasswordResetConfirmation = false
            viewModel.clearMessages()
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

    // MARK: - Request View

    private var requestView: some View {
        VStack(spacing: AppSpacing.xl) {
            // Illustration
            illustrationView(icon: .lockRotation, color: AppColors.primary)

            // Description
            VStack(spacing: AppSpacing.sm) {
                Text("Passwort vergessen?")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Gib deine E-Mail-Adresse ein. Wir senden dir einen Link zum Zuruecksetzen deines Passworts.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // Form card
            Card(hasShadow: true) {
                VStack(spacing: AppSpacing.md) {
                    AuthTextField(
                        title: "E-Mail-Adresse",
                        placeholder: "name@beispiel.de",
                        text: $viewModel.forgotPasswordEmail,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        errorMessage: forgotPasswordEmailError,
                        icon: .envelope
                    )
                    .focused($emailFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        emailFocused = false
                        Task { await viewModel.sendPasswordReset() }
                    }

                    PrimaryButton(
                        "Link senden",
                        icon: .paperplane,
                        isLoading: viewModel.isLoading
                    ) {
                        emailFocused = false
                        Task { await viewModel.sendPasswordReset() }
                    }
                    .disabled(!viewModel.isForgotPasswordFormValid || viewModel.isLoading)
                }
            }

            // Back to login
            Button("Zurueck zur Anmeldung") {
                dismiss()
            }
            .font(AppTypography.buttonSecondary)
            .foregroundStyle(AppColors.primary)
        }
    }

    // MARK: - Confirmation View

    private var confirmationView: some View {
        VStack(spacing: AppSpacing.xl) {
            // Success illustration
            illustrationView(icon: .checkmarkCircleFill, color: AppColors.success)

            // Success message
            VStack(spacing: AppSpacing.sm) {
                Text("E-Mail gesendet!")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                if let message = viewModel.successMessage {
                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                // Email display
                if !viewModel.forgotPasswordEmail.isEmpty {
                    HStack(spacing: AppSpacing.xs) {
                        Image(icon: .envelopeFill)
                            .font(.system(size: AppSpacing.iconSizeSmall))
                            .foregroundStyle(AppColors.primary)

                        Text(viewModel.forgotPasswordEmail)
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
                }
            }

            // Tip card
            Card(hasShadow: false) {
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Image(icon: .infoCircleFill)
                        .font(.system(size: AppSpacing.iconSizeStandard))
                        .foregroundStyle(AppColors.info)

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("Kein E-Mail erhalten?")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("Pruefe deinen Spam-Ordner oder warte einige Minuten. Der Link ist 24 Stunden gueltig.")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineSpacing(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Actions
            VStack(spacing: AppSpacing.sm) {
                PrimaryButton("Zurueck zur Anmeldung") {
                    dismiss()
                }

                SecondaryButton("Erneut senden") {
                    viewModel.showPasswordResetConfirmation = false
                    viewModel.clearMessages()
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func illustrationView(icon: AppIcon, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.1))
                .frame(width: 120, height: 120)

            Circle()
                .fill(color.opacity(0.06))
                .frame(width: 150, height: 150)

            Image(icon: icon)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var forgotPasswordEmailError: String? {
        guard !viewModel.forgotPasswordEmail.isEmpty else { return nil }
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        let isValid = viewModel.forgotPasswordEmail.range(of: pattern, options: .regularExpression) != nil
        return isValid ? nil : "Ungueltige E-Mail-Adresse"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Forgot Password") {
    NavigationStack {
        ForgotPasswordView(viewModel: AuthViewModel())
    }
}

#Preview("Forgot Password - Confirmation") {
    let vm = AuthViewModel()
    vm.forgotPasswordEmail = "max@beispiel.de"
    vm.showPasswordResetConfirmation = true
    vm.successMessage = "Wir haben dir eine E-Mail mit einem Link zum Zuruecksetzen deines Passworts gesendet."
    return NavigationStack {
        ForgotPasswordView(viewModel: vm)
    }
}
#endif
