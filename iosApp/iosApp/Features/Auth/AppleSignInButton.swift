import AuthenticationServices
import SwiftUI

// MARK: - AppleSignInButton

/// A SwiftUI wrapper around Apple's native `ASAuthorizationAppleIDButton`.
///
/// Apple's App Store Review Guidelines (Section 4.8) require that apps using
/// Sign In with Apple display the official Apple-provided button. Using a
/// custom button (like a plain SwiftUI Button) is not permitted.
///
/// This wrapper:
/// - Automatically adapts to the current color scheme (black button in light
///   mode, white button in dark mode) using the `.whiteOutline` style in dark
///   mode and `.black` style in light mode.
/// - Matches the height of the other social sign-in buttons in the auth flow
///   (`AppSpacing.buttonHeightPrimary`).
/// - Forwards taps to the provided `action` closure.
///
/// ## Usage
/// ```swift
/// AppleSignInButton {
///     Task { await viewModel.loginWithApple() }
/// }
/// ```
struct AppleSignInButton: View {

    /// Called when the user taps the button.
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // UIViewRepresentable is used because ASAuthorizationAppleIDButton is
        // a UIKit view. SwiftUI's native SignInWithAppleButton (iOS 14+) is
        // available but does not support the full range of styling options
        // needed to match the app's design system height.
        AppleSignInButtonRepresentable(
            style: colorScheme == .dark ? .whiteOutline : .black,
            action: action
        )
        .frame(height: AppSpacing.buttonHeightPrimary)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
        .accessibilityLabel("Sign in with Apple")
    }
}

// MARK: - AppleSignInButtonRepresentable

/// UIViewRepresentable that wraps `ASAuthorizationAppleIDButton`.
///
/// The button type is `.signIn` which displays "Sign in with Apple".
/// The corner radius is set to match `AppSpacing.cornerRadiusButton`.
private struct AppleSignInButtonRepresentable: UIViewRepresentable {

    let style: ASAuthorizationAppleIDButton.Style
    let action: () -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: style
        )
        button.cornerRadius = AppSpacing.cornerRadiusButton
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleTap),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        // The button style cannot be changed after creation -- a new button
        // would need to be created. In practice, color scheme changes are rare
        // during an active auth session, so this is acceptable.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        private let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }

        @objc func handleTap() {
            action()
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Apple Sign-In Button -- Light") {
    AppleSignInButton { }
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Apple Sign-In Button -- Dark") {
    AppleSignInButton { }
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}
#endif
