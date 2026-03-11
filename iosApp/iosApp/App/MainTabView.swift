import SwiftUI
import UIKit

// MARK: - Tab

/// Represents each tab in the main tab bar.
///
/// The raw value defines the visual order of tabs. All display metadata
/// (icon, label, description) is centralised here so that no other file
/// needs to duplicate these strings.
enum Tab: Int, CaseIterable, Identifiable {
    case dashboard = 0
    case workout
    case history
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
        case .history:   return .rectangleStackFill
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
        case .history:   return "History"
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
        case .history:   return "All your past workouts will appear here."
        case .stats:     return "Daily, weekly, and monthly statistics will appear here."
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
        case .history:   return "tab_history"
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
/// Similarly, `NotificationsViewModel` is owned here so the in-app banner
/// overlay is driven by the same state as the notification list.
struct MainTabView: View {

    /// The currently selected tab. Defaults to `.dashboard` and is never
    /// written to persistent storage, satisfying the "Tab-Auswahl nicht
    /// persistent" acceptance criterion.
    @State private var selectedTab: Tab = .dashboard

    /// Single source of truth for friends data -- shared between the tab-bar
    /// badge and the FriendsView so they always reflect the same state.
    @StateObject private var friendsViewModel = FriendsViewModel()

    /// Single source of truth for notifications -- shared between the in-app
    /// banner overlay and the NotificationsView.
    @StateObject private var notificationsViewModel = NotificationsViewModel()

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

                // History tab -- real implementation (Task 3.9)
                NavigationStack {
                    HistoryView()
                }
                .tabItem {
                    Label(Tab.history.label, icon: Tab.history.icon)
                }
                .tag(Tab.history)
                .accessibilityIdentifier(Tab.history.accessibilityIdentifier)

                // Stats tab -- real implementation (Task 3.8)
                NavigationStack {
                    StatsView()
                }
                .tabItem {
                    Label(Tab.stats.label, icon: Tab.stats.icon)
                }
                .tag(Tab.stats)
                .accessibilityIdentifier(Tab.stats.accessibilityIdentifier)

                // Friends tab -- passes the shared ViewModel so the badge and
                // the list are always in sync.
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

            // In-app notification banner -- slides in when a new unread
            // notification arrives while the user is in the app.
            if let banner = notificationsViewModel.banner {
                NotificationBannerOverlay(item: banner) {
                    notificationsViewModel.dismissBanner()
                }
                .padding(.top, 8)
                .zIndex(10)
            }
        }
        .onAppear {
            friendsViewModel.loadIncomingRequests()
            notificationsViewModel.loadNotifications()
            handleShieldWorkoutFlag()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            handleShieldWorkoutFlag()
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
