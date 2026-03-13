import SwiftUI

// MARK: - SetUsernameView

/// Shown after a first-time social sign-in (or on session restore when the user
/// has not yet chosen a username) to let the user pick their unique handle.
///
/// **Why this screen exists**
/// When a user signs in with Apple or Google for the first time, no username
/// is set. This screen lets the user choose a unique username before entering
/// the app. The screen is shown exactly once -- as soon as the user has a
/// username, it is never shown again.
///
/// **Username rules**
/// - 3 to 20 characters
/// - Only lowercase letters (a-z), digits (0-9), and underscores (_)
/// - Must be unique across all users
///
/// **Availability feedback**
/// As the user types, the view debounces input and checks availability against
/// the backend. A green checkmark means the username is available; a red X
/// means it is taken.
///
/// Note: This view is still named `SetDisplayNameView` in the file for
/// backward compatibility with the existing navigation wiring in PushUpApp.swift.
struct SetDisplayNameView: View {

    @ObservedObject var viewModel: AuthViewModel
    @FocusState private var fieldFocused: Bool

    /// Whether the Continue button should be enabled.
    private var canSubmit: Bool {
        viewModel.isUsernameLocallyValid
            && viewModel.isUsernameAvailable == true
            && !viewModel.isSavingUsername
            && !viewModel.isCheckingUsername
    }

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Illustration + headline
                headerSection
                    .padding(.bottom, AppSpacing.xxl)

                // Username input card
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
                Text("Choose your username")
                    .font(AppTypography.title1)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Your unique handle for finding and being found by friends.")
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
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Username")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textSecondary)

                // Input field with availability indicator
                HStack(spacing: AppSpacing.sm) {
                    TextField("e.g. john_doe", text: $viewModel.usernameInput)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .focused($fieldFocused)
                        .onChange(of: viewModel.usernameInput) { _, _ in
                            viewModel.onUsernameInputChanged()
                        }
                        .onSubmit {
                            guard canSubmit else { return }
                            fieldFocused = false
                            Task { await viewModel.saveUsername() }
                        }

                    // Availability indicator
                    availabilityIndicator
                }
                .padding(.vertical, AppSpacing.sm)
                .padding(.horizontal, AppSpacing.md)
                .background(AppColors.backgroundSecondary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip))

                // Validation / availability message
                validationMessage

                // Rules hint
                Text("3-20 characters. Letters, digits, and underscores only.")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    // MARK: - Availability Indicator

    @ViewBuilder
    private var availabilityIndicator: some View {
        let trimmed = viewModel.usernameInput.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty {
            EmptyView()
        } else if viewModel.isCheckingUsername {
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 20, height: 20)
        } else if let available = viewModel.isUsernameAvailable {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? AppColors.success : AppColors.error)
                .font(.system(size: 20))
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Validation Message

    @ViewBuilder
    private var validationMessage: some View {
        let trimmed = viewModel.usernameInput.trimmingCharacters(in: .whitespaces).lowercased()
        if !trimmed.isEmpty {
            if let localError = viewModel.usernameValidationError {
                Text(localError)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.error)
            } else if let available = viewModel.isUsernameAvailable {
                Text(available ? "Username is available!" : "Username is already taken.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(available ? AppColors.success : AppColors.error)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Confirm Button

    private var confirmButton: some View {
        PrimaryButton(
            "Continue",
            icon: .arrowRight,
            isLoading: viewModel.isSavingUsername
        ) {
            fieldFocused = false
            Task { await viewModel.saveUsername() }
        }
        .disabled(!canSubmit)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("SetUsernameView - Available") {
    let vm = AuthViewModel()
    vm.usernameInput = "john_doe"
    vm.isUsernameAvailable = true
    return SetDisplayNameView(viewModel: vm)
}

#Preview("SetUsernameView - Taken") {
    let vm = AuthViewModel()
    vm.usernameInput = "john"
    vm.isUsernameAvailable = false
    return SetDisplayNameView(viewModel: vm)
}

#Preview("SetUsernameView - Empty") {
    SetDisplayNameView(viewModel: AuthViewModel())
}
#endif
