import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - FriendCodeView

/// Full-screen view showing the user's own friend code, QR code, privacy
/// controls, and a reset button.
///
/// Presented as a sheet from `AddFriendSheet` (the "My Code" tab).
struct FriendCodeView: View {

    @StateObject private var viewModel = FriendCodeViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    codeCard
                    privacySection
                    resetSection
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.screenVerticalBottom)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("My Friend Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
        .onAppear { viewModel.loadMyCode() }
        .alert("Reset Code?", isPresented: $viewModel.showResetConfirm) {
            Button("Reset", role: .destructive) { viewModel.resetCode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current code will stop working immediately. Anyone who saved it will need your new code.")
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.resetError != nil },
            set: { if !$0 { viewModel.dismissResetError() } }
        )) {
            Button("OK", role: .cancel) { viewModel.dismissResetError() }
        } message: {
            Text(viewModel.resetError ?? "")
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.privacyUpdateError != nil },
            set: { if !$0 { viewModel.dismissPrivacyError() } }
        )) {
            Button("OK", role: .cancel) { viewModel.dismissPrivacyError() }
        } message: {
            Text(viewModel.privacyUpdateError ?? "")
        }
    }

    // MARK: - Code card

    @ViewBuilder
    private var codeCard: some View {
        Card(hasShadow: true) {
            VStack(spacing: AppSpacing.md) {
                if viewModel.isLoading && viewModel.code.isEmpty {
                    codeCardSkeleton
                } else if let error = viewModel.loadError {
                    codeLoadError(error)
                } else {
                    codeCardContent
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
        }
    }

    private var codeCardContent: some View {
        VStack(spacing: AppSpacing.md) {
            // QR code
            QRCodeView(content: viewModel.deepLink)
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)

            // Code text
            VStack(spacing: AppSpacing.xxs) {
                Text(formattedCode(viewModel.code))
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
                    .tracking(6)

                Text("Friend Code")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }

            // Action buttons
            HStack(spacing: AppSpacing.sm) {
                // Copy code
                ShareButton(
                    label: "Copy",
                    systemImage: "doc.on.doc",
                    action: {
                        UIPasteboard.general.string = viewModel.code
                    }
                )

                // Share deep-link
                if !viewModel.deepLink.isEmpty {
                    ShareLink(item: viewModel.deepLink) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(AppColors.textOnPrimary)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.xs)
                            .background(AppColors.primary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var codeCardSkeleton: some View {
        VStack(spacing: AppSpacing.md) {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
                .fill(AppColors.backgroundTertiary)
                .frame(width: 180, height: 180)
                .shimmer()

            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.backgroundTertiary)
                .frame(width: 200, height: 40)
                .shimmer()
        }
    }

    private func codeLoadError(_ message: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppColors.error)
            Text(message)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") { viewModel.loadMyCode() }
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.primary)
        }
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - Privacy section

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Privacy")
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)

            VStack(spacing: AppSpacing.xs) {
                ForEach(FriendCodePrivacyOption.allCases) { option in
                    PrivacyOptionRow(
                        option: option,
                        isSelected: viewModel.privacy == option,
                        isLoading: viewModel.isUpdatingPrivacy,
                        onSelect: { viewModel.updatePrivacy(option) }
                    )
                }
            }
        }
    }

    // MARK: - Reset section

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Code Management")
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)

            Card(hasShadow: false) {
                Button {
                    viewModel.confirmReset()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Generate New Code")
                                .font(AppTypography.bodySemibold)
                                .foregroundStyle(AppColors.error)
                            Text("Your current code will stop working immediately.")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        if viewModel.isResetting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.error)
                        }
                    }
                    .padding(.vertical, AppSpacing.xs)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isResetting || viewModel.code.isEmpty)
            }
        }
    }

    // MARK: - Helpers

    /// Inserts a space every 4 characters for readability: "AB3X7K2M" -> "AB3X 7K2M"
    private func formattedCode(_ code: String) -> String {
        guard code.count > 4 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 4)
        return String(code[..<mid]) + " " + String(code[mid...])
    }
}

// MARK: - PrivacyOptionRow

private struct PrivacyOptionRow: View {

    let option: FriendCodePrivacyOption
    let isSelected: Bool
    let isLoading: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppSpacing.sm) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? AppColors.primary.opacity(0.12) : AppColors.backgroundTertiary)
                        .frame(width: 40, height: 40)
                    Image(systemName: option.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? AppColors.primary : AppColors.textSecondary)
                }

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(isSelected ? AppColors.primary : AppColors.textPrimary)
                    Text(option.description)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Selection indicator
                if isLoading && isSelected {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? AppColors.primary : AppColors.textTertiary)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                isSelected
                    ? AppColors.primary.opacity(0.06)
                    : AppColors.backgroundSecondary,
                in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
                    .strokeBorder(
                        isSelected ? AppColors.primary.opacity(0.3) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - ShareButton

private struct ShareButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    @State private var copied = false

    var body: some View {
        Button {
            action()
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { copied = false }
            }
        } label: {
            Label(copied ? "Copied!" : label, systemImage: copied ? "checkmark" : systemImage)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.primary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.primary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - QRCodeView

/// Generates and displays a QR code for the given string content.
struct QRCodeView: View {

    let content: String

    var body: some View {
        if let image = generateQRCode(from: content) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.backgroundTertiary)
                .overlay(
                    Image(systemName: "qrcode")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(AppColors.textTertiary)
                )
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let context = CIContext()
        let filter  = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up so the QR code is crisp at display size.
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Shimmer (local extension)

private extension View {
    func shimmer() -> some View {
        self.modifier(FriendCodeShimmerModifier())
    }
}

private struct FriendCodeShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.35), location: 0.4),
                            .init(color: .white.opacity(0.35), location: 0.6),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .init(x: phase, y: 0.5),
                        endPoint: .init(x: phase + 1, y: 0.5)
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("FriendCodeView") {
    FriendCodeView()
}
#endif
