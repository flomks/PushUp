import SwiftUI

// MARK: - Metrics (Figma / React export: IPhoneMockup + Sidebar)

enum SideMenuAnimations {
    /// Spring tuned to mirror the Figma export (`stiffness: 300`, `damping: 30`).
    static func card(reduceMotion: Bool) -> Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.25)
        }
        return .spring(response: 0.35, dampingFraction: 0.78)
    }
}

enum SideMenuMetrics {
    /// Horizontal offset of the main app card when the menu is open.
    static let cardOffsetX: CGFloat = 260
    /// Scale of the card when the menu is open.
    static let cardScale: CGFloat = 0.88
    /// Corner radius of the card when the menu is open.
    static let cardCornerRadius: CGFloat = 30
    /// Leading width reserved for menu content and tappable rows.
    static let menuContentWidth: CGFloat = 280
    /// Leading inset for the floating menu button (hamburger).
    static let menuButtonLeading: CGFloat = 20
    /// Extra offset below the top safe area for the menu button (~70pt from screen top in export).
    static let menuButtonTopBelowSafeArea: CGFloat = 26
    static let menuButtonSize: CGFloat = 36
    /// Horizontal padding for menu inner content (px-6 in export).
    static let menuHorizontalPadding: CGFloat = 24
    /// Top / bottom padding aligned with export (pt-[59] pb-[34]).
    static let menuTopPadding: CGFloat = 59
    static let menuBottomPadding: CGFloat = 34
}

// MARK: - Gradient backdrop (behind the sliding card)

/// Full-screen emerald → teal gradient; fades in/out with the menu.
struct SideMenuGradientLayer: View {
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
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3),
            value: isOpen
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Interactive overlay (above TabView)

/// Menu rows on the leading strip and tap-to-dismiss on the rest (matches export `left: 280` overlay behaviour).
struct SideMenuInteractiveLayer: View {
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

    // MARK: - Menu column

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
        withAnimation(SideMenuAnimations.card(reduceMotion: reduceMotion)) {
            isOpen = false
        }
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

// MARK: - Menu item model

private struct SideMenuItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tab: Tab?
    let highlight: Bool
    let showNewBadge: Bool
}

// MARK: - Floating menu button

struct SideMenuHamburgerButton: View {
    @Environment(\.safeAreaInsets) private var safeAreaInsets

    let action: () -> Void

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
        .padding(.top, safeAreaInsets.top + SideMenuMetrics.menuButtonTopBelowSafeArea)
        .accessibilityLabel("Open menu")
    }
}
