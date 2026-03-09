import SwiftUI

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

    /// The localised label shown below the tab bar icon and in the
    /// navigation bar title.
    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .workout:   return "Workout"
        case .history:   return "History"
        case .stats:     return "Stats"
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
        case .profile:   return "tab_profile"
        case .settings:  return "tab_settings"
        }
    }
}

// MARK: - MainTabView

/// Root navigation container for the PushUp app.
///
/// Renders a `TabView` with six tabs. Each tab owns its own `NavigationStack`
/// so that navigation state is independent per tab. The selected tab is
/// intentionally **not** persisted -- the app always opens on the Dashboard
/// tab after a cold launch, as required by Task 3.3.
struct MainTabView: View {

    /// The currently selected tab. Defaults to `.dashboard` and is never
    /// written to persistent storage, satisfying the "Tab-Auswahl nicht
    /// persistent" acceptance criterion.
    @State private var selectedTab: Tab = .dashboard

    /// Shared ViewModels for Friends and Notifications so badge counts and
    /// banners are available across the whole tab bar.
    @StateObject private var friendsViewModel = FriendsViewModel()
    @StateObject private var notificationsViewModel = NotificationsViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                // Dashboard tab
                NavigationStack {
                    DashboardView(selectedTab: $selectedTab)
                }
                .tabItem {
                    Label(Tab.dashboard.label, icon: Tab.dashboard.icon)
                }
                .tag(Tab.dashboard)
                .accessibilityIdentifier(Tab.dashboard.accessibilityIdentifier)

                // Workout tab
                WorkoutView()
                    .tabItem {
                        Label(Tab.workout.label, icon: Tab.workout.icon)
                    }
                    .tag(Tab.workout)
                    .accessibilityIdentifier(Tab.workout.accessibilityIdentifier)

                // History tab
                NavigationStack {
                    HistoryView()
                }
                .tabItem {
                    Label(Tab.history.label, icon: Tab.history.icon)
                }
                .tag(Tab.history)
                .accessibilityIdentifier(Tab.history.accessibilityIdentifier)

                // Stats tab
                NavigationStack {
                    StatsView()
                }
                .tabItem {
                    Label(Tab.stats.label, icon: Tab.stats.icon)
                }
                .tag(Tab.stats)
                .accessibilityIdentifier(Tab.stats.accessibilityIdentifier)

                // Friends tab (new)
                FriendsView()
                    .tabItem {
                        Label(Tab.friends.label, icon: Tab.friends.icon)
                    }
                    .tag(Tab.friends)
                    .badge(friendsViewModel.pendingRequestCount > 0
                           ? friendsViewModel.pendingRequestCount : 0)
                    .accessibilityIdentifier(Tab.friends.accessibilityIdentifier)

                // Profile tab
                NavigationStack {
                    ProfileView()
                }
                .tabItem {
                    Label(Tab.profile.label, icon: Tab.profile.icon)
                }
                .tag(Tab.profile)
                .accessibilityIdentifier(Tab.profile.accessibilityIdentifier)

                // Settings tab
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

            // Offline banner overlay -- slides in from the top when offline.
            OfflineBanner()

            // In-app notification banner -- slides in when a new notification arrives.
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
        }
    }
}

// MARK: - TabPlaceholderView

/// Placeholder screen displayed inside each tab until the real feature
/// view is implemented.
///
/// All display data (icon, title, description) is derived from the `Tab`
/// enum so there is a single source of truth for tab metadata.
///
/// Replace individual cases in `MainTabView.body` with the real feature
/// views as they are implemented (Task 3.5 Dashboard, Task 3.6 Workout,
/// Task 3.8 Stats, Task 3.10 Profile, Task 3.11 Settings).
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
