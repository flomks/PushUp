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
    case stats
    case friends
    case profile
    case settings

    var id: Int { rawValue }

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

    /// Tabs shown as dedicated icons in the bottom bar (first 4).
    /// Profile and Settings live behind the "More" button — matching the system TabView behaviour with 6 tabs.
    static let primaryBarTabs: [Tab] = [.dashboard, .workout, .stats, .friends]

    /// Tabs accessible via the "More" menu.
    static let moreTabs: [Tab] = [.profile, .settings]
}

// MARK: - MainTabView

struct MainTabView: View {

    @State private var selectedTab: Tab = .dashboard
    @StateObject private var friendsViewModel = FriendsViewModel()
    @State private var pendingFriendCode: String? = nil
    @State private var showFriendCodeSheet = false
    @StateObject private var friendCodeViewModel = FriendCodeViewModel()
    @State private var isSideMenuOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            SideMenuGradientLayer(isOpen: isSideMenuOpen, reduceMotion: reduceMotion)
                .zIndex(0)

            appShell
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: isSideMenuOpen ? SideMenuMetrics.cardCornerRadius : 0,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: isSideMenuOpen ? SideMenuMetrics.cardCornerRadius : 0,
                        style: .continuous
                    )
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: isSideMenuOpen ? 1 : 0)
                }
                .shadow(
                    color: isSideMenuOpen ? Color.black.opacity(0.55) : .clear,
                    radius: isSideMenuOpen ? 30 : 0,
                    x: -14,
                    y: 0
                )
                .scaleEffect(isSideMenuOpen ? SideMenuMetrics.cardScale : 1, anchor: .center)
                .offset(x: isSideMenuOpen ? SideMenuMetrics.cardOffsetX : 0)
                .allowsHitTesting(!isSideMenuOpen)
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

            OfflineBanner()
                .frame(maxWidth: .infinity, alignment: .top)
                .zIndex(4)
        }
        .onAppear {
            configureNavigationBarAppearance()
            friendsViewModel.loadIncomingRequests()
            handleShieldWorkoutFlag()
            friendCodeViewModel.onFriendAdded = { [weak friendsViewModel] in
                friendsViewModel?.loadFriends()
                friendsViewModel?.loadLeaderboard()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            handleShieldWorkoutFlag()
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .sheet(isPresented: $showFriendCodeSheet) {
            EnterFriendCodeSheet(viewModel: friendCodeViewModel)
        }
    }

    // MARK: - App shell (content + custom tab bar, NO system TabView)

    private var appShell: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Only render the active tab — avoids 6 simultaneous scroll views destroying performance.
                tabContent(for: selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                CustomTabBar(
                    selectedTab: $selectedTab,
                    pendingRequestCount: friendsViewModel.pendingRequestCount
                )
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: Tab) -> some View {
        switch tab {
        case .dashboard:
            NavigationStack {
                DashboardView(selectedTab: $selectedTab)
            }
            .accessibilityIdentifier(Tab.dashboard.accessibilityIdentifier)
        case .workout:
            NavigationStack {
                WorkoutSelectionView()
            }
            .accessibilityIdentifier(Tab.workout.accessibilityIdentifier)
        case .stats:
            NavigationStack {
                StatsView()
            }
            .accessibilityIdentifier(Tab.stats.accessibilityIdentifier)
        case .friends:
            FriendsView(viewModel: friendsViewModel)
                .accessibilityIdentifier(Tab.friends.accessibilityIdentifier)
        case .profile:
            NavigationStack {
                ProfileView()
            }
            .accessibilityIdentifier(Tab.profile.accessibilityIdentifier)
        case .settings:
            NavigationStack {
                SettingsView()
            }
            .accessibilityIdentifier(Tab.settings.accessibilityIdentifier)
        }
    }

    // MARK: - Navigation bar appearance

    /// Opaque navigation bar so scrolled content never shows through the header.
    private func configureNavigationBarAppearance() {
        let opaque = UINavigationBarAppearance()
        opaque.configureWithOpaqueBackground()
        opaque.backgroundColor = UIColor(AppColors.backgroundPrimary)
        opaque.shadowColor = UIColor.white.withAlphaComponent(0.08)

        let transparent = UINavigationBarAppearance()
        transparent.configureWithTransparentBackground()

        UINavigationBar.appearance().standardAppearance = opaque
        UINavigationBar.appearance().scrollEdgeAppearance = transparent
        UINavigationBar.appearance().compactAppearance = opaque
        UINavigationBar.appearance().tintColor = UIColor(AppColors.primary)
    }

    // MARK: - Deep links

    private func handleShieldWorkoutFlag() {
        let defaults = UserDefaults(suiteName: "group.com.flomks.pushup")
        guard defaults?.bool(forKey: "shield.shouldOpenWorkout") == true else { return }
        defaults?.removeObject(forKey: "shield.shouldOpenWorkout")
        defaults?.synchronize()
        selectedTab = .workout
    }

    private func handleDeepLink(_ url: URL) {
        let extracted: String?

        if url.scheme == "https",
           url.host == "pushup.weareo.fun",
           url.pathComponents.count >= 3,
           url.pathComponents[1] == "friend" {
            extracted = url.pathComponents[2].uppercased()
        } else if url.scheme == "pushup", url.host == "friend-code" {
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

// MARK: - Custom Tab Bar

private struct CustomTabBar: View {
    @Binding var selectedTab: Tab
    let pendingRequestCount: Int

    @State private var showMoreSheet = false

    private let inactiveColor = Color(white: 0.45)

    private var isMoreActive: Bool {
        Tab.moreTabs.contains(selectedTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 0.33)

            HStack(spacing: 0) {
                ForEach(Tab.primaryBarTabs) { tab in
                    tabButton(for: tab)
                }

                moreButton
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
        .background {
            AppColors.backgroundPrimary
                .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showMoreSheet) {
            moreSheet
        }
    }

    private func tabButton(for tab: Tab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(icon: tab.icon)
                        .font(.system(size: 22, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? AppColors.primary : inactiveColor)

                    if tab == .friends && pendingRequestCount > 0 {
                        Text("\(pendingRequestCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.red, in: Circle())
                            .offset(x: 8, y: -4)
                    }
                }
                .frame(height: 24)

                Text(tab.label)
                    .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? AppColors.primary : inactiveColor)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tab.accessibilityIdentifier)
    }

    private var moreButton: some View {
        Button {
            showMoreSheet = true
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 22, weight: isMoreActive ? .semibold : .regular))
                    .foregroundStyle(isMoreActive ? AppColors.primary : inactiveColor)
                    .frame(height: 24)

                Text("More")
                    .font(.system(size: 10, weight: isMoreActive ? .semibold : .regular))
                    .foregroundStyle(isMoreActive ? AppColors.primary : inactiveColor)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab_more")
    }

    private var moreSheet: some View {
        NavigationStack {
            List {
                ForEach(Tab.moreTabs) { tab in
                    Button {
                        showMoreSheet = false
                        selectedTab = tab
                    } label: {
                        Label {
                            Text(tab.label)
                                .foregroundStyle(AppColors.textPrimary)
                        } icon: {
                            Image(icon: tab.icon)
                                .foregroundStyle(AppColors.primary)
                        }
                    }
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showMoreSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Side menu internals

private enum SideMenuAnimations {
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

private struct SideMenuGradientLayer: View {
    let isOpen: Bool
    let reduceMotion: Bool

    private var emerald: Color { Color(red: 5 / 255, green: 150 / 255, blue: 105 / 255) }
    private var teal: Color { Color(red: 15 / 255, green: 118 / 255, blue: 110 / 255) }

    var body: some View {
        LinearGradient(colors: [emerald, teal], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            .opacity(isOpen ? 1 : 0)
            .animation(SideMenuAnimations.card(reduceMotion: reduceMotion), value: isOpen)
            .allowsHitTesting(false)
    }
}

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
                        .onTapGesture { closeMenu() }
                        .accessibilityLabel("Dismiss menu")
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
        .task(id: isOpen) {
            if isOpen { await refreshUser() }
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

            Button { closeMenu() } label: {
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
        Button { handleMenuItem(item) } label: {
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
        .animation(rowAnimation(delayIndex: index), value: isOpen)
    }

    private var logoutRow: some View {
        Button { confirmLogout = true } label: {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowAnimation(delayIndex: Int) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.2) }
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
            if let tab = item.tab { selectedTab = tab }
            closeMenu()
        }
    }

    private func closeMenu() { isOpen = false }

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
