import SwiftUI

// MARK: - Tab

/// Represents each tab in the main tab bar.
///
/// The raw value is used as the accessibility identifier and for equality
/// checks. The order of cases defines the visual order of tabs.
enum Tab: Int, CaseIterable {
    case dashboard = 0
    case workout
    case stats
    case profile
    case settings

    /// The SF Symbol name shown in the tab bar item.
    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .workout:   return "figure.strengthtraining.traditional"
        case .stats:     return "chart.bar.fill"
        case .profile:   return "person.fill"
        case .settings:  return "gearshape.fill"
        }
    }

    /// The localised label shown below the tab bar icon.
    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .workout:   return "Workout"
        case .stats:     return "Stats"
        case .profile:   return "Profile"
        case .settings:  return "Settings"
        }
    }
}

// MARK: - MainTabView

/// Root navigation container for the PushUp app.
///
/// Renders a `TabView` with five tabs. Each tab owns its own `NavigationStack`
/// so that navigation state is independent per tab. The selected tab is
/// intentionally **not** persisted -- the app always opens on the Dashboard
/// tab after a cold launch, as required by Task 3.3.
struct MainTabView: View {

    /// The currently selected tab. Defaults to `.dashboard` and is never
    /// written to persistent storage, satisfying the "Tab-Auswahl nicht
    /// persistent" acceptance criterion.
    @State private var selectedTab: Tab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(Tab.allCases, id: \.self) { tab in
                NavigationStack {
                    placeholderView(for: tab)
                }
                .tabItem {
                    Label(tab.label, systemImage: tab.icon)
                }
                .tag(tab)
            }
        }
        .tint(AppColors.primaryInline)
    }

    // MARK: - Placeholder routing

    /// Returns the placeholder view for the given tab.
    ///
    /// Each placeholder will be replaced by the real screen implementation in
    /// subsequent tasks (3.5 Dashboard, 3.6 Workout, 3.8 Stats, 3.10 Profile,
    /// 3.11 Settings).
    @ViewBuilder
    private func placeholderView(for tab: Tab) -> some View {
        switch tab {
        case .dashboard: DashboardPlaceholderView()
        case .workout:   WorkoutPlaceholderView()
        case .stats:     StatsPlaceholderView()
        case .profile:   ProfilePlaceholderView()
        case .settings:  SettingsPlaceholderView()
        }
    }
}

// MARK: - Placeholder Views

// ---------------------------------------------------------------------------
// Each placeholder follows the same visual pattern:
//   - Full-screen background using AppColors
//   - Centered SF Symbol icon (large, tinted)
//   - Screen title in AppTypography.title1
//   - Short description in AppTypography.subheadline
//   - Navigation title set to the tab label
//
// This gives a consistent, recognisable shell that can be replaced screen by
// screen without touching MainTabView.
// ---------------------------------------------------------------------------

/// Placeholder for the Dashboard screen (Task 3.5).
struct DashboardPlaceholderView: View {
    var body: some View {
        PlaceholderScreenView(
            icon: "house.fill",
            title: "Dashboard",
            description: "Dein Zeitguthaben und die Tages-Statistiken erscheinen hier."
        )
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// Placeholder for the Workout screen (Task 3.6).
struct WorkoutPlaceholderView: View {
    var body: some View {
        PlaceholderScreenView(
            icon: "figure.strengthtraining.traditional",
            title: "Workout",
            description: "Starte hier ein Workout und zaehle deine Push-Ups in Echtzeit."
        )
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// Placeholder for the Stats screen (Task 3.8).
struct StatsPlaceholderView: View {
    var body: some View {
        PlaceholderScreenView(
            icon: "chart.bar.fill",
            title: "Stats",
            description: "Taeglich, woechentlich und monatliche Statistiken erscheinen hier."
        )
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// Placeholder for the Profile screen (Task 3.10).
struct ProfilePlaceholderView: View {
    var body: some View {
        PlaceholderScreenView(
            icon: "person.fill",
            title: "Profile",
            description: "Dein Profil, Avatar und Account-Informationen erscheinen hier."
        )
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
    }
}

/// Placeholder for the Settings screen (Task 3.11).
struct SettingsPlaceholderView: View {
    var body: some View {
        PlaceholderScreenView(
            icon: "gearshape.fill",
            title: "Settings",
            description: "Push-Up-Rate, Benachrichtigungen und weitere Einstellungen erscheinen hier."
        )
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - PlaceholderScreenView

/// Reusable full-screen placeholder used by all tab placeholder views.
///
/// Displays a large SF Symbol, a title, and a short description centred on
/// the screen. Uses the app's design system tokens so it already looks
/// on-brand and adapts to Light / Dark Mode automatically.
private struct PlaceholderScreenView: View {

    let icon: String
    let title: String
    let description: String

    var body: some View {
        ZStack {
            AppColors.backgroundPrimaryInline
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                Image(systemName: icon)
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(AppColors.primaryInline)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: AppSpacing.xs) {
                    Text(title)
                        .font(AppTypography.title1)
                        .foregroundStyle(AppColors.textPrimaryInline)

                    Text(description)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondaryInline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }
            }
            .padding(AppSpacing.xl)
        }
    }
}

// MARK: - Preview

#Preview("MainTabView") {
    MainTabView()
}

#Preview("Dashboard Placeholder") {
    NavigationStack {
        DashboardPlaceholderView()
    }
}

#Preview("Workout Placeholder") {
    NavigationStack {
        WorkoutPlaceholderView()
    }
}
