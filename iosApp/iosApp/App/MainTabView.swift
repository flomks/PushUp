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
    case stats
    case profile
    case settings

    // MARK: Identifiable

    var id: Int { rawValue }

    // MARK: Display metadata

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

    /// The localised label shown below the tab bar icon and in the
    /// navigation bar title.
    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .workout:   return "Workout"
        case .stats:     return "Stats"
        case .profile:   return "Profile"
        case .settings:  return "Settings"
        }
    }

    /// A short placeholder description shown on the placeholder screen
    /// until the real feature view replaces it.
    var placeholderDescription: String {
        switch self {
        case .dashboard: return "Dein Zeitguthaben und die Tages-Statistiken erscheinen hier."
        case .workout:   return "Starte hier ein Workout und zaehle deine Push-Ups in Echtzeit."
        case .stats:     return "Taeglich, woechentlich und monatliche Statistiken erscheinen hier."
        case .profile:   return "Dein Profil, Avatar und Account-Informationen erscheinen hier."
        case .settings:  return "Push-Up-Rate, Benachrichtigungen und weitere Einstellungen erscheinen hier."
        }
    }

    /// A stable string identifier used for UI tests and accessibility.
    var accessibilityIdentifier: String {
        switch self {
        case .dashboard: return "tab_dashboard"
        case .workout:   return "tab_workout"
        case .stats:     return "tab_stats"
        case .profile:   return "tab_profile"
        case .settings:  return "tab_settings"
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
            ForEach(Tab.allCases) { tab in
                NavigationStack {
                    TabPlaceholderView(tab: tab)
                }
                .tabItem {
                    Label(tab.label, systemImage: tab.icon)
                }
                .tag(tab)
                .accessibilityIdentifier(tab.accessibilityIdentifier)
            }
        }
        .tint(AppColors.primaryInline)
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
            AppColors.backgroundPrimaryInline
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                Image(systemName: tab.icon)
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(AppColors.primaryInline)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: AppSpacing.xs) {
                    Text(tab.label)
                        .font(AppTypography.title1)
                        .foregroundStyle(AppColors.textPrimaryInline)

                    Text(tab.placeholderDescription)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondaryInline)
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
