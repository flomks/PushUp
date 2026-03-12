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
                    // Post-login destination: the full 6-tab main navigation.
                    MainTabView()
                        .transition(.opacity)

                case .needsDisplayName:
                    // First social sign-in: user must choose a display name
                    // before entering the app. The auto-generated placeholder
                    // is already saved in the DB so it is never NULL.
                    SetDisplayNameView(viewModel: authViewModel)
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
        }
        .task {
            // Attempt to restore an existing Supabase session so the user
            // does not have to log in again after restarting the app.
            await authViewModel.restoreSession()

            // Dismiss the splash overlay after a brief moment to allow the
            // first SwiftUI render pass to complete. Using structured
            // concurrency so the timer is automatically cancelled if the
            // view disappears.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                showSplash = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userDidSignOut)) { _ in
            // ProfileViewModel posts this notification when the user signs out
            // or deletes their account. Transition back to the auth flow.
            Task { await authViewModel.signOut() }
        }
    }
}

// MARK: - SplashOverlayView

/// Branded overlay that **exactly** mirrors the `LaunchScreen.storyboard`
/// appearance so the transition from the system launch screen is seamless.
///
/// Uses the same `LaunchLogo` image asset, `LaunchBackground` color, font
/// sizes, and layout offsets as the storyboard to avoid any visual jump.
private struct SplashOverlayView: View {

    var body: some View {
        ZStack {
            // Must match the LaunchScreen.storyboard background color.
            Color("LaunchBackground")
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Must match the storyboard's 200x200 LaunchLogo imageView.
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)

                // Must match the storyboard's 32pt boldSystem font label.
                Text("PushUp")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)

                // Must match the storyboard's 16pt system font tagline.
                Text("Earn your screen time")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
            }
            // The storyboard centres the group with a -60pt vertical offset.
            .offset(y: -30)
        }
    }
}
