import SwiftUI
import UIKit

// MARK: - Tab

/// Represents each tab in the main tab bar.
///
/// The raw value defines the visual order of tabs. All display metadata
/// (icon, label, description) is centralised here so that no other file
/// needs to duplicate these strings.
///
/// History has been moved inside the Stats tab (as a segment) so that the
/// Friends tab can occupy a dedicated, prominent position in the tab bar.
enum Tab: Int, CaseIterable, Identifiable {
    case dashboard = 0
    case workout
    case stats
    case friends
    case profile
    case settings

    // MARK: Identifiable

    var id: Int { rawValue }

    // MARK: Display metadata

    /// The type-safe SF Symbol shown in the tab bar item.
    var icon: AppIcon {
        switch self {
        case .dashboard: return .houseFill
        case .workout:   return .figureStrengthTraining
        case .stats:     return .chartBarFill
        case .friends:   return .person2Fill
        case .profile:   return .personFill
        case .settings:  return .gearshapeFill
        }
    }

    /// The localised label shown below the tab bar icon and in the
    /// navigation bar title.
    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .workout:   return "Workout"
        case .stats:     return "Stats"
        case .friends:   return "Friends"
        case .profile:   return "Profile"
        case .settings:  return "Settings"
        }
    }

    /// A short placeholder description shown on the placeholder screen
    /// until the real feature view replaces it.
    var placeholderDescription: String {
        switch self {
        case .dashboard: return "Your time credit and daily statistics will appear here."
        case .workout:   return "Start a workout here and count your push-ups in real time."
        case .stats:     return "Daily, weekly, monthly statistics and workout history will appear here."
        case .friends:   return "Find friends, manage requests, and see your friends list."
        case .profile:   return "Your profile, avatar, and account information will appear here."
        case .settings:  return "Push-up rate, notifications, and other settings will appear here."
        }
    }

    /// A stable string identifier used for UI tests and accessibility.
    var accessibilityIdentifier: String {
        switch self {
        case .dashboard: return "tab_dashboard"
        case .workout:   return "tab_workout"
        case .stats:     return "tab_stats"
        case .friends:   return "tab_friends"
        case .profile:   return "tab_profile"
        case .settings:  return "tab_settings"
        }
    }
}

// MARK: - MainTabView

/// Root navigation container for the PushUp app.
///
/// Renders a `TabView` with seven tabs. Each tab owns its own `NavigationStack`
/// so that navigation state is independent per tab. The selected tab is
/// intentionally **not** persisted -- the app always opens on the Dashboard
/// tab after a cold launch, as required by Task 3.3.
///
/// A single `FriendsViewModel` instance is owned here and passed into
/// `FriendsView` so that the tab-bar badge and the list share the same data.
struct MainTabView: View {

    /// The currently selected tab. Defaults to `.dashboard` and is never
    /// written to persistent storage, satisfying the "Tab-Auswahl nicht
    /// persistent" acceptance criterion.
    @State private var selectedTab: Tab = .dashboard

    /// Single source of truth for friends data -- shared between the tab-bar
    /// badge and the FriendsView so they always reflect the same state.
    @StateObject private var friendsViewModel = FriendsViewModel()

    /// When a friend-code deep-link is opened, this holds the code so the
    /// Friends tab can present the Enter Code sheet automatically.
    @State private var pendingFriendCode: String? = nil

    /// Controls the Enter Code sheet triggered by a deep-link.
    @State private var showFriendCodeSheet = false

    /// Shared ViewModel for friend code operations (used by deep-link sheet).
    @StateObject private var friendCodeViewModel = FriendCodeViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                // Dashboard tab -- real implementation (Task 3.5)
                NavigationStack {
                    DashboardView(selectedTab: $selectedTab)
                }
                .tabItem {
                    Label(Tab.dashboard.label, icon: Tab.dashboard.icon)
                }
                .tag(Tab.dashboard)
                .accessibilityIdentifier(Tab.dashboard.accessibilityIdentifier)

                // Workout tab -- real implementation (Task 3.6)
                WorkoutView()
                    .tabItem {
                        Label(Tab.workout.label, icon: Tab.workout.icon)
                    }
                    .tag(Tab.workout)
                    .accessibilityIdentifier(Tab.workout.accessibilityIdentifier)

                // Stats tab -- real implementation (Task 3.8)
                // History is accessible via the "History" segment inside StatsView.
                NavigationStack {
                    StatsView()
                }
                .tabItem {
                    Label(Tab.stats.label, icon: Tab.stats.icon)
                }
                .tag(Tab.stats)
                .accessibilityIdentifier(Tab.stats.accessibilityIdentifier)

                // Friends tab -- dedicated tab so the social / competition
                // features are always one tap away. Passes the shared ViewModel
                // so the badge and the list are always in sync.
                FriendsView(viewModel: friendsViewModel)
                    .tabItem {
                        Label(Tab.friends.label, icon: Tab.friends.icon)
                    }
                    .tag(Tab.friends)
                    .badge(friendsViewModel.pendingRequestCount)
                    .accessibilityIdentifier(Tab.friends.accessibilityIdentifier)

                // Profile tab -- real implementation (Task 3.10)
                NavigationStack {
                    ProfileView()
                }
                .tabItem {
                    Label(Tab.profile.label, icon: Tab.profile.icon)
                }
                .tag(Tab.profile)
                .accessibilityIdentifier(Tab.profile.accessibilityIdentifier)

                // Settings tab -- real implementation (Task 3.11)
                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label(Tab.settings.label, icon: Tab.settings.icon)
                }
                .tag(Tab.settings)
                .accessibilityIdentifier(Tab.settings.accessibilityIdentifier)
            }
            .tint(AppColors.primary)

            // Offline banner overlay (Task 3.14) -- slides in from the top
            // when the device loses connectivity and slides out on reconnect.
            OfflineBanner()
        }
        .onAppear {
            friendsViewModel.loadIncomingRequests()
            handleShieldWorkoutFlag()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            handleShieldWorkoutFlag()
        }
        // Handle pushup://friend-code/<CODE> deep-links
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .sheet(isPresented: $showFriendCodeSheet) {
            EnterFriendCodeSheet(viewModel: friendCodeViewModel)
        }
    }

    // MARK: - Shield Deep Link

    /// Checks whether the ShieldActionExtension requested a direct jump to the
    /// Workout tab (user tapped "Do Push-Ups Now" on the shield). If so,
    /// switches to the Workout tab and clears the flag.
    private func handleShieldWorkoutFlag() {
        let defaults = UserDefaults(suiteName: "group.com.flomks.pushup")
        guard defaults?.bool(forKey: "shield.shouldOpenWorkout") == true else { return }
        defaults?.removeObject(forKey: "shield.shouldOpenWorkout")
        defaults?.synchronize()
        selectedTab = .workout
    }

    // MARK: - Friend Code Deep Link

    /// Handles friend-code deep-links in two formats:
    ///   - Universal Link:  `https://pushup.weareo.fun/friend/<CODE>`
    ///   - Custom scheme:   `pushup://friend-code/<CODE>`
    ///
    /// Switches to the Friends tab and opens the Enter Code sheet with
    /// the code pre-filled so the user only needs to tap "Add Friend".
    private func handleDeepLink(_ url: URL) {
        let extracted: String?

        if url.scheme == "https",
           url.host == "pushup.weareo.fun",
           url.pathComponents.count >= 3,
           url.pathComponents[1] == "friend" {
            // Universal Link: https://pushup.weareo.fun/friend/AB3X7K2M
            extracted = url.pathComponents[2].uppercased()
        } else if url.scheme == "pushup", url.host == "friend-code" {
            // Custom scheme: pushup://friend-code/AB3X7K2M
            extracted = url.pathComponents
                .filter { $0 != "/" }
                .first?
                .uppercased()
        } else {
            return
        }

        guard let code = extracted, !code.isEmpty else { return }

        selectedTab = .friends
        friendCodeViewModel.enteredCode = code
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showFriendCodeSheet = true
        }
    }
}

// MARK: - TabPlaceholderView

/// Placeholder screen displayed inside each tab until the real feature
/// view is implemented.
///
/// All display data (icon, title, description) is derived from the `Tab`
/// enum so there is a single source of truth for tab metadata.
struct TabPlaceholderView: View {

    let tab: Tab

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                Image(icon: tab.icon)
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: AppSpacing.xs) {
                    Text(tab.label)
                        .font(AppTypography.title1)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(tab.placeholderDescription)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }
            }
            .padding(AppSpacing.xl)
        }
        .navigationTitle(tab.label)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Previews

#Preview("MainTabView") {
    MainTabView()
}

#Preview("Placeholder - Dashboard") {
    NavigationStack {
        TabPlaceholderView(tab: .dashboard)
    }
}

#Preview("Placeholder - Workout") {
    NavigationStack {
        TabPlaceholderView(tab: .workout)
    }
}

#Preview("Placeholder - Stats") {
    NavigationStack {
        TabPlaceholderView(tab: .stats)
    }
}

#Preview("Placeholder - Friends") {
    NavigationStack {
        TabPlaceholderView(tab: .friends)
    }
}

#Preview("Placeholder - Profile") {
    NavigationStack {
        TabPlaceholderView(tab: .profile)
    }
}

#Preview("Placeholder - Settings") {
    NavigationStack {
        TabPlaceholderView(tab: .settings)
    }
}
