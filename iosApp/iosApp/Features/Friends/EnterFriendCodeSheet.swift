import SwiftUI

// MARK: - EnterFriendCodeSheet

/// Sheet that lets the user type in or scan a friend code.
///
/// Can be used in two ways:
///   1. As a standalone sheet (e.g. from a deep-link) -- wraps itself in a
///      NavigationStack and shows a "Done" button.
///   2. Embedded inside `AddFriendSheet` (the "Enter Code" tab) -- the
///      parent provides the navigation chrome; set `standalone = false`.
struct EnterFriendCodeSheet: View {

    @ObservedObject var viewModel: FriendCodeViewModel
    @Environment(\.dismiss) private var dismiss

    /// When `true` the view wraps itself in a NavigationStack with a Done
    /// button and sheet presentation modifiers. Set to `false` when embedding
    /// inside another NavigationStack.
    var standalone: Bool = true

    /// Focus state for the code text field.
    @FocusState private var isFieldFocused: Bool

    /// Controls the full-screen QR scanner.
    @State private var showScanner = false

    var body: some View {
        Group {
            if standalone {
                NavigationStack {
                    innerContent
                        .navigationTitle("Enter Friend Code")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { dismiss() }
                                    .font(AppTypography.bodySemibold)
                                    .foregroundStyle(AppColors.primary)
                            }
                        }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            } else {
                innerContent
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView { code in
                // Code scanned successfully: fill the field and dismiss scanner
                viewModel.enteredCode = code
                showScanner = false
                // Auto-submit after a brief moment so the user sees the filled code
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    viewModel.useFriendCode()
                }
            } onCancel: {
                showScanner = false
            }
        }
        .alert(
            viewModel.useCodeSuccess?.title ?? "",
            isPresented: Binding(
                get: { viewModel.useCodeSuccess != nil },
                set: { if !$0 { viewModel.dismissUseCodeSuccess() } }
            )
        ) {
            Button("Great!", role: .cancel) {
                viewModel.dismissUseCodeSuccess()
                if standalone { dismiss() }
            }
        } message: {
            Text(viewModel.useCodeSuccess?.message ?? "")
        }
        .alert("Could Not Use Code", isPresented: Binding(
            get: { viewModel.useCodeError != nil },
            set: { if !$0 { viewModel.dismissUseCodeError() } }
        )) {
            Button("OK", role: .cancel) { viewModel.dismissUseCodeError() }
        } message: {
            Text(viewModel.useCodeError ?? "")
        }
        .onAppear { isFieldFocused = true }
    }

    private var innerContent: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.lg)
            Spacer()
        }
        .background(AppColors.backgroundPrimary)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: AppSpacing.lg) {
            // Illustration
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(AppColors.primary)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: AppSpacing.xxs) {
                    Text("Add by Code")
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Type your friend's code or scan their QR code.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Code input field + scan button side by side
            codeInputRow

            // Submit button
            submitButton
        }
    }

    // MARK: - Code input row (text field + scan button)

    private var codeInputRow: some View {
        VStack(spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                // Text field
                TextField("e.g. AB3X7K2M", text: $viewModel.enteredCode)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($isFieldFocused)
                    .onChange(of: viewModel.enteredCode) { _, newValue in
                        let cleaned = newValue
                            .uppercased()
                            .filter { $0.isLetter || $0.isNumber }
                            .prefix(16)
                        if viewModel.enteredCode != String(cleaned) {
                            viewModel.enteredCode = String(cleaned)
                        }
                    }
                    .padding(.vertical, AppSpacing.sm)
                    .padding(.horizontal, AppSpacing.md)
                    .background(
                        AppColors.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                            .strokeBorder(
                                isFieldFocused ? AppColors.primary.opacity(0.5) : Color.clear,
                                lineWidth: 1.5
                            )
                    )

                // QR scan button
                Button {
                    isFieldFocused = false
                    showScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 52, height: 52)
                        .background(
                            AppColors.primary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan QR code")
            }

            if !viewModel.enteredCode.isEmpty {
                Text("\(viewModel.enteredCode.count) / 16 characters")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    // MARK: - Submit button

    private var submitButton: some View {
        Button {
            isFieldFocused = false
            viewModel.useFriendCode()
        } label: {
            Group {
                if viewModel.isUsingCode {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Add Friend")
                        .font(AppTypography.bodySemibold)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
            .background(
                viewModel.enteredCode.count >= 4
                    ? AppColors.primary
                    : AppColors.primary.opacity(0.4),
                in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.enteredCode.count < 4 || viewModel.isUsingCode)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("EnterFriendCodeSheet") {
    EnterFriendCodeSheet(viewModel: FriendCodeViewModel())
}
#endif
