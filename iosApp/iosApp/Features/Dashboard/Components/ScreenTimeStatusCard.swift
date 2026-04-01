import SwiftUI
import UIKit

// MARK: - ScreenTimeStatusCard

/// Dashboard card showing the current Screen Time / App Blocking status.
///
/// Displayed on the Dashboard when Screen Time is authorized and apps are selected.
/// Shows:
/// - Current blocking state (active / inactive)
/// - Today's app usage time (OS-tracked, reinstall-proof)
/// - Quick link to per-app usage detail (ScreenTimeAppDetailView)
/// - Quick link to Screen Time settings
///
/// When Screen Time is not set up, shows a compact placeholder so the dashboard row stays visible
/// (the slot still exists in layout JSON — an empty `body` looked like “no widget” and broke edit/remove UX).
struct ScreenTimeStatusCard: View {

    @ObservedObject private var manager = ScreenTimeManager.shared
    private let usageStore = ScreenTimeUsageStore.shared

    @State private var todayUsageSeconds: Int = 0

    private var showError: Binding<Bool> {
        Binding(
            get: { manager.errorMessage != nil },
            set: { if !$0 { manager.clearError() } }
        )
    }

    var body: some View {
        Group {
            if manager.authorizationStatus == .authorized, hasSelection {
                cardContent
            } else if manager.authorizationStatus == .authorized {
                authorizedNoSelectionPlaceholder
            } else {
                notAuthorizedPlaceholder
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screen Time")
        .task { todayUsageSeconds = usageStore.todayUsageSeconds }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            todayUsageSeconds = usageStore.todayUsageSeconds
        }
        .alert("Error", isPresented: showError) {
            Button("OK", role: .cancel) { manager.clearError() }
        } message: {
            Text(manager.errorMessage ?? "")
        }
    }

    private var hasSelection: Bool {
        guard let selection = manager.activitySelection else { return false }
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    private func dashboardChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(DashboardWidgetChrome.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardWidgetChrome()
    }

    // MARK: - Placeholders (dashboard slot always visible)

    private var notAuthorizedPlaceholder: some View {
        dashboardChrome {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Image(icon: .hourglassFill)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                    .symbolRenderingMode(.hierarchical)
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppSpacing.xs)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Screen Time access")
                        .font(AppTypography.headline)
                        .foregroundStyle(DashboardWidgetChrome.labelPrimary)
                    Text(notAuthorizedExplanation)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                notAuthorizedActionButton

                NavigationLink {
                    ScreenTimeSettingsView()
                } label: {
                    Text("All Screen Time options")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.top, AppSpacing.xxs)
            }
        }
    }

    private var notAuthorizedExplanation: String {
        switch manager.authorizationStatus {
        case .denied:
            return "Screen Time permission was denied. Open Settings to enable access for this app, then you can track usage and block apps when your time credit runs out."
        case .unavailable:
            return "Screen Time controls are not available on this device or iOS version."
        case .notDetermined, .authorized:
            return "Grant access so PushUp can show today’s usage here and pause selected apps when you’ve used your screen-time credit."
        }
    }

    @ViewBuilder
    private var notAuthorizedActionButton: some View {
        switch manager.authorizationStatus {
        case .notDetermined:
            PrimaryButton(
                "Allow Screen Time access",
                icon: .checkmarkShield,
                isLoading: manager.isRequestingAuthorization
            ) {
                Task { await manager.requestAuthorization() }
            }
        case .denied:
            PrimaryButton("Open Settings", icon: .gearshapeFill) {
                openAppSettings()
            }
        case .unavailable, .authorized:
            EmptyView()
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var authorizedNoSelectionPlaceholder: some View {
        dashboardChrome {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                screenTimeHeaderTitle
                Text("Choose which apps or categories to monitor for usage and blocking.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink {
                    ScreenTimeSettingsView()
                } label: {
                    Text("Choose Apps")
                        .font(AppTypography.buttonSecondary)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        dashboardChrome {
            VStack(spacing: AppSpacing.sm) {
                HStack {
                    screenTimeHeaderTitle

                    Spacer()

                    statusBadge
                }

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)

                HStack(spacing: AppSpacing.md) {
                    NavigationLink {
                        ScreenTimeAppDetailView()
                    } label: {
                        VStack(spacing: AppSpacing.xxs) {
                            Image(icon: .hourglassBottomHalf)
                                .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                                .foregroundStyle(usageColor)
                            Text(formatSeconds(todayUsageSeconds))
                                .font(AppTypography.bodySemibold)
                                .foregroundStyle(DashboardWidgetChrome.labelPrimary)
                                .monospacedDigit()
                            Text("Used Today")
                                .font(AppTypography.caption1)
                                .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 36)

                    VStack(spacing: AppSpacing.xxs) {
                        Image(icon: manager.isBlocking ? .lockApp : .checkmarkShield)
                            .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                            .foregroundStyle(manager.isBlocking ? AppColors.error : DashboardWidgetChrome.accentPositive)
                        Text(manager.isBlocking ? "Blocked" : "Open")
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(DashboardWidgetChrome.labelPrimary)
                        Text("App Access")
                            .font(AppTypography.caption1)
                            .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 36)

                    NavigationLink {
                        ScreenTimeSettingsView()
                    } label: {
                        VStack(spacing: AppSpacing.xxs) {
                            Image(icon: .gearshapeFill)
                                .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.75))
                            Text("Settings")
                                .font(AppTypography.bodySemibold)
                                .foregroundStyle(Color.white.opacity(0.9))
                            Text("Configure")
                                .font(AppTypography.caption1)
                                .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    ScreenTimeAppDetailView()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "app.badge.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                        Text("View per-app usage for today")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(Color.white.opacity(0.85))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DashboardWidgetChrome.labelMuted)
                    }
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, AppSpacing.xs)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip))
                }
                .buttonStyle(.plain)

                if manager.isBlocking {
                    blockingBanner
                }

                if todayUsageSeconds > 0 {
                    systemTrackingBadge
                }
            }
        }
        .accessibilityLabel("Screen Time status card")
    }

    private var screenTimeHeaderTitle: some View {
        HStack(spacing: 10) {
            Image(icon: .hourglassFill)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(DashboardWidgetChrome.labelSecondary)
            Text("Screen Time")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DashboardWidgetChrome.labelPrimary)
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: AppSpacing.xxs) {
            Circle()
                .fill(manager.isBlocking ? AppColors.error : DashboardWidgetChrome.accentPositive)
                .frame(width: 6, height: 6)
            Text(manager.isBlocking ? "Blocking" : "Active")
                .font(AppTypography.caption2)
                .foregroundStyle(manager.isBlocking ? AppColors.error : DashboardWidgetChrome.accentPositive)
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, 3)
        .background(
            (manager.isBlocking ? AppColors.error : DashboardWidgetChrome.accentPositive).opacity(0.12),
            in: Capsule()
        )
    }

    // MARK: - Blocking Banner

    private var blockingBanner: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(icon: .lockApp)
                .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                .foregroundStyle(AppColors.error)

            Text("Apps are blocked. Do push-ups to earn more time credit!")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.error)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(AppSpacing.xs)
        .background(AppColors.error.opacity(0.08), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip))
    }

    // MARK: - System Tracking Badge

    private var systemTrackingBadge: some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColors.success)
            Text("Tracked by iOS Screen Time")
                .font(AppTypography.caption2)
                .foregroundStyle(DashboardWidgetChrome.labelSecondary)
            Spacer()
        }
    }

    // MARK: - Helpers

    private var usageColor: Color {
        if todayUsageSeconds == 0 { return DashboardWidgetChrome.labelSecondary }
        let fraction = Double(todayUsageSeconds) / 7200.0
        if fraction >= 1.0 { return AppColors.error }
        if fraction >= 0.8 { return AppColors.warning }
        return Color.white.opacity(0.85)
    }

    private func formatSeconds(_ seconds: Int) -> String {
        if seconds == 0 { return "0m" }
        if seconds < 60 { return "\(seconds)s" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ScreenTimeStatusCard - Active") {
    NavigationStack {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                ScreenTimeStatusCard()
            }
            .padding(AppSpacing.md)
        }
        .background(DashboardWidgetChrome.pageBackground)
    }
}
#endif
