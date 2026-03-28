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
        case .workout:   return "Choose from push-ups, plank, squats, and more to earn screen time."
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

    /// Figma-style slide-out menu: pushes the whole tab shell aside (implementations below).
    @State private var isSideMenuOpen = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Unstyled tab container — same shape as root `MainTabView` before the side drawer (e.g. 9a6dedf).
    @ViewBuilder
    private var tabShell: some View {
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

            // Workout tab -- exercise selection hub with navigation
            NavigationStack {
                WorkoutSelectionView()
            }
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
    }

    var body: some View {
        // `topLeading` so the menu button stays at the upper-left (`.top` centers horizontally).
        ZStack(alignment: .topLeading) {
            SideMenuGradientLayer(isOpen: isSideMenuOpen, reduceMotion: reduceMotion)
                .zIndex(0)

            // Modifier order mirrors the Figma export structure:
            //   inner: round corners + border + shadow  →  outer: offset + scale
            // `.mask` instead of `.clipShape` preserves safe-area propagation
            // so header/footer stay edge-to-edge when closed (radius 0 = no-op).
            tabShell
                .mask {
                    RoundedRectangle(
                        cornerRadius: isSideMenuOpen ? SideMenuMetrics.cardCornerRadius : 0,
                        style: .continuous
                    )
                    .ignoresSafeArea()
                }
                .overlay {
                    RoundedRectangle(
                        cornerRadius: isSideMenuOpen ? SideMenuMetrics.cardCornerRadius : 0,
                        style: .continuous
                    )
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: isSideMenuOpen ? 1 : 0)
                    .ignoresSafeArea()
                }
                .shadow(
                    color: isSideMenuOpen ? Color.black.opacity(0.55) : .clear,
                    radius: isSideMenuOpen ? 30 : 0,
                    x: -14,
                    y: 0
                )
                .offset(x: isSideMenuOpen ? SideMenuMetrics.cardOffsetX : 0)
                .scaleEffect(isSideMenuOpen ? SideMenuMetrics.cardScale : 1, anchor: .center)
                .animation(SideMenuAnimations.card(reduceMotion: reduceMotion), value: isSideMenuOpen)
                .zIndex(1)

            SideMenuInteractiveLayer(
                isOpen: $isSideMenuOpen,
                selectedTab: $selectedTab,
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(2)
            .allowsHitTesting(isSideMenuOpen)

            if !isSideMenuOpen {
                SideMenuHamburgerButton {
                    isSideMenuOpen = true
                }
                .zIndex(3)
            }

            // Offline banner overlay (Task 3.14) -- slides in from the top
            // when the device loses connectivity and slides out on reconnect.
            OfflineBanner()
                .frame(maxWidth: .infinity, alignment: .top)
                .zIndex(4)
        }
        .onAppear {
            friendsViewModel.loadIncomingRequests()
            handleShieldWorkoutFlag()
            // Wire deep-link scanner: auto-refresh friends after a successful add.
            friendCodeViewModel.onFriendAdded = { [weak friendsViewModel] in
                friendsViewModel?.loadFriends()
                friendsViewModel?.loadLeaderboard()
            }
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

// MARK: - Side menu (Figma export — kept in this file so the target always compiles)

private enum SideMenuAnimations {
    /// Spring tuned to mirror the Figma export (`stiffness: 300`, `damping: 30`).
    static func card(reduceMotion: Bool) -> Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.25)
        }
        return .spring(response: 0.35, dampingFraction: 0.78)
    }
}

private enum SideMenuMetrics {
    static let cardOffsetX: CGFloat = 260
    static let cardScale: CGFloat = 0.88
    static let cardCornerRadius: CGFloat = 30
    static let menuContentWidth: CGFloat = 280
    static let menuButtonLeading: CGFloat = 20
    static let menuButtonTopBelowSafeArea: CGFloat = 26
    static let menuButtonSize: CGFloat = 36
    static let menuHorizontalPadding: CGFloat = 24
    static let menuTopPadding: CGFloat = 59
    static let menuBottomPadding: CGFloat = 34
}

/// Full-screen emerald → teal gradient; fades in/out with the menu.
private struct SideMenuGradientLayer: View {
    let isOpen: Bool
    let reduceMotion: Bool

    private var emerald: Color {
        Color(red: 5 / 255, green: 150 / 255, blue: 105 / 255)
    }

    private var teal: Color {
        Color(red: 15 / 255, green: 118 / 255, blue: 110 / 255)
    }

    var body: some View {
        LinearGradient(
            colors: [emerald, teal],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .opacity(isOpen ? 1 : 0)
        .animation(SideMenuAnimations.card(reduceMotion: reduceMotion), value: isOpen)
        .allowsHitTesting(false)
    }
}

/// Menu rows on the leading strip and tap-to-dismiss on the rest (matches export `left: 280` overlay behaviour).
private struct SideMenuInteractiveLayer: View {
    @Binding var isOpen: Bool
    @Binding var selectedTab: Tab
    let reduceMotion: Bool

    @Environment(\.openURL) private var openURL

    @State private var displayName: String = ""
    @State private var subtitle: String = "Member"
    @State private var confirmLogout = false

    private let rowIconFont: Font = .system(size: 20, weight: .semibold)

    var body: some View {
        Group {
            if isOpen {
                HStack(spacing: 0) {
                    menuColumn
                        .frame(width: SideMenuMetrics.menuContentWidth, alignment: .leading)

                    Color.clear
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture {
                            closeMenu()
                        }
                        .accessibilityLabel("Dismiss menu")
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
        .task(id: isOpen) {
            if isOpen {
                await refreshUser()
            }
        }
        .alert("Log out?", isPresented: $confirmLogout) {
            Button("Cancel", role: .cancel) {}
            Button("Log out", role: .destructive) {
                NotificationCenter.default.post(name: .userDidSignOut, object: nil)
                closeMenu()
            }
        } message: {
            Text("You will need to sign in again to use the app.")
        }
    }

    private var menuColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.bottom, AppSpacing.xl)

            userBlock
                .padding(.bottom, AppSpacing.xl)

            VStack(spacing: 4) {
                ForEach(Array(menuItems.enumerated()), id: \.element.id) { index, item in
                    menuRow(item: item, index: index)
                }
            }

            Spacer(minLength: 0)

            logoutRow
                .padding(.top, AppSpacing.md)
        }
        .padding(.horizontal, SideMenuMetrics.menuHorizontalPadding)
        .padding(.top, SideMenuMetrics.menuTopPadding)
        .padding(.bottom, SideMenuMetrics.menuBottomPadding)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var headerRow: some View {
        HStack {
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(icon: .personFill)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

            Spacer()

            Button {
                closeMenu()
            } label: {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close menu")
        }
    }

    private var userBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayName.isEmpty ? " " : displayName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var menuItems: [SideMenuItem] {
        [
            SideMenuItem(id: "profile", title: "Profile", symbol: "person.fill", tab: .profile, highlight: false, showNewBadge: false),
            SideMenuItem(id: "dashboard", title: "Dashboard", symbol: "square.grid.2x2.fill", tab: .dashboard, highlight: false, showNewBadge: false),
            SideMenuItem(id: "workouts", title: "Workouts", symbol: "figure.strengthtraining.traditional", tab: .workout, highlight: false, showNewBadge: false),
            SideMenuItem(id: "achievements", title: "Achievements", symbol: "trophy.fill", tab: .profile, highlight: false, showNewBadge: false),
            SideMenuItem(id: "friends", title: "Friends", symbol: "person.2.fill", tab: .friends, highlight: false, showNewBadge: false),
            SideMenuItem(id: "gopro", title: "Go Pro", symbol: "crown.fill", tab: nil, highlight: true, showNewBadge: true),
            SideMenuItem(id: "settings", title: "Settings", symbol: "gearshape.fill", tab: .settings, highlight: false, showNewBadge: false),
            SideMenuItem(id: "help", title: "Help & Support", symbol: "questionmark.circle", tab: nil, highlight: false, showNewBadge: false),
        ]
    }

    private func menuRow(item: SideMenuItem, index: Int) -> some View {
        Button {
            handleMenuItem(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(rowIconFont)
                    .foregroundStyle(.white)
                    .frame(width: 24)

                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                if item.showNewBadge {
                    Text("NEW")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.99, green: 0.93, blue: 0.55))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.yellow.opacity(0.2)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(item.highlight ? Color.white.opacity(0.2) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isOpen ? 1 : 0)
        .offset(x: isOpen ? 0 : -20)
        .animation(
            rowAnimation(delayIndex: index),
            value: isOpen
        )
    }

    private var logoutRow: some View {
        Button {
            confirmLogout = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(rowIconFont)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 24)

                Text("Logout")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowAnimation(delayIndex: Int) -> Animation {
        if reduceMotion {
            return .easeOut(duration: 0.2)
        }
        let delay = isOpen ? Double(delayIndex) * 0.05 : 0
        return .easeOut(duration: 0.25).delay(delay)
    }

    private func handleMenuItem(_ item: SideMenuItem) {
        switch item.id {
        case "gopro":
            closeMenu()
        case "help":
            openURL(AppInfo.supportURL)
            closeMenu()
        default:
            if let tab = item.tab {
                selectedTab = tab
            }
            closeMenu()
        }
    }

    private func closeMenu() {
        isOpen = false
    }

    @MainActor
    private func refreshUser() async {
        guard let user = await AuthService.shared.getCurrentUser() else { return }
        displayName = user.displayName
        if let name = user.username, !name.isEmpty {
            subtitle = "@\(name)"
        } else {
            subtitle = "Member"
        }
    }
}

private struct SideMenuItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tab: Tab?
    let highlight: Bool
    let showNewBadge: Bool
}

private struct SideMenuHamburgerButton: View {

    let action: () -> Void

    /// Avoids `@Environment(\.safeAreaInsets)` — some toolchains resolve `EdgeInsets` incorrectly for that key.
    private var keyWindowSafeAreaTop: CGFloat {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        return window?.safeAreaInsets.top ?? 0
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .opacity(0.85)

                Circle()
                    .fill(Color.white.opacity(0.1))

                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: SideMenuMetrics.menuButtonSize, height: SideMenuMetrics.menuButtonSize)
        }
        .buttonStyle(.plain)
        .padding(.leading, SideMenuMetrics.menuButtonLeading)
        .padding(.top, keyWindowSafeAreaTop + SideMenuMetrics.menuButtonTopBelowSafeArea)
        .accessibilityLabel("Open menu")
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
