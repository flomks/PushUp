import SwiftUI

// MARK: - SetDisplayNameView

/// Shown after a first-time social sign-in to let the user choose their display name.
///
/// **Why this screen exists**
/// When a user signs in with Apple or Google for the first time, the KMP layer
/// creates a User record with an auto-generated display name (the email prefix).
/// This screen lets the user replace that placeholder with a real name before
/// entering the app.
///
/// **Safety guarantee**
/// The auto-generated name is written to the local DB immediately on sign-in,
/// so the display name is never NULL even if the user kills the app before
/// completing this screen. The name they choose here overwrites the placeholder.
///
/// **New-user detection**
/// `AuthViewModel.handleSocialSignInSuccess` sets `authState = .needsDisplayName`
/// when the stored display name looks auto-generated. Returning users skip this
/// screen entirely and go straight to `.authenticated`.
struct SetDisplayNameView: View {

    @ObservedObject var viewModel: AuthViewModel
    @FocusState private var fieldFocused: Bool

    private var isValid: Bool {
        !viewModel.displayNameInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Illustration + headline
                headerSection
                    .padding(.bottom, AppSpacing.xxl)

                // Name input card
                inputCard
                    .padding(.horizontal, AppSpacing.screenHorizontal)

                Spacer()
                Spacer()

                // Confirm button
                confirmButton
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.screenVerticalBottom)
            }
        }
        .onAppear {
            // Auto-focus the field so the keyboard appears immediately.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                fieldFocused = true
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

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: AppSpacing.md) {
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
                    .shadow(color: AppColors.primary.opacity(0.3), radius: 16, x: 0, y: 8)

                Image(icon: .person)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: AppSpacing.xs) {
                Text("What's your name?")
                    .font(AppTypography.title1)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("This is how other users will see you in PushUp.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }
        }
    }

    // MARK: - Input Card

    private var inputCard: some View {
        Card(hasShadow: true) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Display Name")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textSecondary)

                TextField("e.g. Alex or Alex M.", text: $viewModel.displayNameInput)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($fieldFocused)
                    .onSubmit {
                        guard isValid else { return }
                        Task { await viewModel.saveDisplayName() }
                    }
                    .padding(.vertical, AppSpacing.sm)
                    .padding(.horizontal, AppSpacing.md)
                    .background(AppColors.backgroundSecondary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip))

                Text("You can change this later in your profile.")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    // MARK: - Confirm Button

    private var confirmButton: some View {
        PrimaryButton(
            "Continue",
            icon: .arrowRight,
            isLoading: viewModel.isSavingDisplayName
        ) {
            fieldFocused = false
            Task { await viewModel.saveDisplayName() }
        }
        .disabled(!isValid || viewModel.isSavingDisplayName)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("SetDisplayNameView") {
    let vm = AuthViewModel()
    vm.displayNameInput = "Alex"
    return SetDisplayNameView(viewModel: vm)
}

#Preview("SetDisplayNameView - Empty") {
    SetDisplayNameView(viewModel: AuthViewModel())
}
#endif
