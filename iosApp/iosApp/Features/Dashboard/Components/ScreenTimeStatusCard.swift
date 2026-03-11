import SwiftUI

// MARK: - ScreenTimeStatusCard

/// Dashboard card showing the current Screen Time / App Blocking status.
///
/// Displayed on the Dashboard when Screen Time is authorized.
/// Shows:
/// - Current blocking state (active / inactive)
/// - Today's app usage time
/// - Quick link to Screen Time settings
///
/// Hidden entirely when Screen Time is not set up (not authorized).
struct ScreenTimeStatusCard: View {

    @ObservedObject private var manager = ScreenTimeManager.shared
    private let usageStore = ScreenTimeUsageStore.shared

    /// Today's total usage in seconds (read from App Group store).
    private var todayUsageSeconds: Int {
        usageStore.todayUsageSeconds
    }

    var body: some View {
        // Only show when Screen Time is authorized and has a selection
        if manager.authorizationStatus == .authorized, hasSelection {
            cardContent
        }
    }

    private var hasSelection: Bool {
        guard let selection = manager.activitySelection else { return false }
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    // MARK: - Card Content

    private var cardContent: some View {
        Card {
            VStack(spacing: AppSpacing.sm) {
                // Header
                HStack {
                    Label("Screen Time", icon: .hourglassFill)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    // Status badge
                    statusBadge
                }

                Divider()

                // Metrics row
                HStack(spacing: AppSpacing.md) {
                    // Today's usage
                    metricItem(
                        icon: .hourglassBottomHalf,
                        value: formatSeconds(todayUsageSeconds),
                        label: "Used Today",
                        color: usageColor
                    )

                    Divider().frame(height: 36)

                    // Blocking state
                    metricItem(
                        icon: manager.isBlocking ? .lockApp : .checkmarkShield,
                        value: manager.isBlocking ? "Blocked" : "Open",
                        label: "App Access",
                        color: manager.isBlocking ? AppColors.error : AppColors.success
                    )

                    Divider().frame(height: 36)

                    // Navigate to Screen Time settings
                    NavigationLink {
                        ScreenTimeSettingsView()
                    } label: {
                        VStack(spacing: AppSpacing.xxs) {
                            Image(icon: .gearshapeFill)
                                .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                                .foregroundStyle(AppColors.primary)
                            Text("Settings")
                                .font(AppTypography.bodySemibold)
                                .foregroundStyle(AppColors.primary)
                            Text("Configure")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }

                // Warning banner when blocking is active
                if manager.isBlocking {
                    blockingBanner
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screen Time status card")
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: AppSpacing.xxs) {
            Circle()
                .fill(manager.isBlocking ? AppColors.error : AppColors.success)
                .frame(width: 6, height: 6)
            Text(manager.isBlocking ? "Blocking" : "Active")
                .font(AppTypography.caption2)
                .foregroundStyle(manager.isBlocking ? AppColors.error : AppColors.success)
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, 3)
        .background(
            (manager.isBlocking ? AppColors.error : AppColors.success).opacity(0.1),
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

    // MARK: - Metric Item

    private func metricItem(
        icon: AppIcon,
        value: String,
        label: String,
        color: Color
    ) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Image(icon: icon)
                .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                .foregroundStyle(color)

            Text(value)
                .font(AppTypography.bodySemibold)
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()

            Text(label)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var usageColor: Color {
        if todayUsageSeconds == 0 { return AppColors.textSecondary }
        // Color based on usage relative to a 2-hour "reasonable" daily limit
        let fraction = Double(todayUsageSeconds) / 7200.0
        if fraction >= 1.0 { return AppColors.error }
        if fraction >= 0.8 { return AppColors.warning }
        return AppColors.primary
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
        .background(AppColors.backgroundPrimary)
    }
}
#endif
