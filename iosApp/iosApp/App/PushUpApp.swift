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
struct RootView: View {

    @StateObject private var authViewModel = AuthViewModel()

    /// Persisted flag: `true` after the user has completed onboarding once.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false

    /// Controls whether the onboarding sheet is presented over the auth flow.
    @State private var showOnboarding: Bool = false

    var body: some View {
        Group {
            switch authViewModel.authState {
            case .authenticated:
                // Post-login destination: the full 5-tab main navigation
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
        .animation(.easeInOut(duration: 0.35), value: authViewModel.authState == .authenticated)
        .onAppear {
            if !hasSeenOnboarding {
                showOnboarding = true
            }
        }
    }
}
