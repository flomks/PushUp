import SwiftUI

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
///
/// Used across login, registration, and forgot-password screens.
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
///
/// Used across login and registration screens.
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
