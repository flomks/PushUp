import SwiftUI
import UIKit

/// Root entry point of the PushUp iOS application.
///
/// Koin is initialised in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
/// before the first SwiftUI scene is rendered, ensuring all KMP-managed
/// dependencies are available when the UI starts.
@main
struct PushUpApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - RootView

/// Manages the top-level navigation between onboarding, auth, and the main app.
///
/// Flow:
///   1. First launch  -> OnboardingView -> LoginView -> MainTabView
///   2. Return launch -> LoginView -> MainTabView  (onboarding skipped)
///   3. Authenticated -> MainTabView directly (future: restore session)
///
/// A branded splash overlay fades out after the initial load to provide a
/// smooth visual bridge from the system launch screen.
struct RootView: View {

    @StateObject private var authViewModel = AuthViewModel()

    /// Persisted flag: `true` after the user has completed onboarding once.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false

    /// The user's preferred appearance mode, read directly from `UserDefaults`
    /// so the color scheme is applied at the root level without requiring
    /// the full `SettingsViewModel`.
    @AppStorage(SettingsKeys.appearanceMode) private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    /// Controls whether the onboarding sheet is presented over the auth flow.
    @State private var showOnboarding: Bool = false

    /// Controls the branded splash overlay that fades out on first render.
    @State private var showSplash: Bool = true

    /// The resolved appearance mode from the persisted raw value.
    private var resolvedColorScheme: ColorScheme? {
        (AppearanceMode(rawValue: appearanceModeRaw) ?? .system).colorScheme
    }

    var body: some View {
        ZStack {
            // Main app content
            Group {
                switch authViewModel.authState {
                case .authenticated:
                    // Post-login destination: the full 6-tab main navigation
                    // implemented in Task 3.3 (MainTabView.swift).
                    MainTabView()
                        .transition(.opacity)

                case .unauthenticated, .loading:
                    LoginView(viewModel: authViewModel)
                        .transition(.opacity)
                        .fullScreenCover(isPresented: $showOnboarding) {
                            OnboardingView {
                                hasSeenOnboarding = true
                                showOnboarding = false
                            }
                        }
                }
            }
            .preferredColorScheme(resolvedColorScheme)
            .animation(.easeInOut(duration: 0.35), value: authViewModel.authState)

            // Branded splash overlay -- fades out after a short delay so the
            // transition from the system launch screen is seamless.
            if showSplash {
                SplashOverlayView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            if !hasSeenOnboarding {
                showOnboarding = true
            }
            // Dismiss the splash overlay after a brief moment to allow the
            // first SwiftUI render pass to complete.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}

// MARK: - SplashOverlayView

/// Branded overlay that mirrors the launch screen appearance.
///
/// Shown briefly on app start and fades out smoothly, providing a seamless
/// visual bridge between the system launch screen and the first app screen.
private struct SplashOverlayView: View {

    var body: some View {
        ZStack {
            // Match the launch screen background color
            AppColors.primary
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                // App logo (push-up figure)
                Image(icon: .figureStrengthTraining)
                    .font(.system(size: 80, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: AppSpacing.xs) {
                    Text("PushUp")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Earn your screen time")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }
}
