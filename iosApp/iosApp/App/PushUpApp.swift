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
                // Post-login destination: the main tab bar.
                // Task 3.6 will replace this with the full feature tab bar.
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

// MARK: - MainTabView

/// Placeholder for the main tab bar introduced in Task 3.6.
///
/// Currently wraps the existing `ContentView` (workout demo) so the app
/// remains fully functional after login. Replace the tabs with the real
/// feature screens when Task 3.6 is implemented.
struct MainTabView: View {

    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Workout tab (existing demo screen)
            ContentView()
                .tabItem {
                    Label("Workout", icon: .figureStrengthTraining)
                }
                .tag(0)

            // Dashboard placeholder
            dashboardPlaceholder
                .tabItem {
                    Label("Dashboard", icon: .chartBarFill)
                }
                .tag(1)

            // Profile placeholder
            profilePlaceholder
                .tabItem {
                    Label("Profil", icon: .personFill)
                }
                .tag(2)
        }
        .tint(AppColors.primary)
    }

    // MARK: - Placeholder Tabs

    private var dashboardPlaceholder: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()

            EmptyStateCard(
                icon: .chartBarFill,
                title: "Dashboard",
                message: "Deine Statistiken und Zeitguthaben erscheinen hier. (Task 3.5)"
            )
            .padding(AppSpacing.screenHorizontal)
        }
    }

    private var profilePlaceholder: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()

            EmptyStateCard(
                icon: .personFill,
                title: "Profil",
                message: "Dein Profil und Einstellungen erscheinen hier. (Task 3.7)"
            )
            .padding(AppSpacing.screenHorizontal)
        }
    }
}
