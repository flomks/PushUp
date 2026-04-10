import SwiftUI
import DeviceActivity
import FamilyControls

// MARK: - ScreenTimeAppUsageView

/// Inline card showing per-app usage for today.
///
/// Designed to be embedded inside a ScrollView / LazyVStack.
/// Shows a compact summary with a "See All" link to `ScreenTimeAppDetailView`.
///
/// On iOS 16.4+ the card embeds a `DeviceActivityReport` which is rendered
/// by the `DeviceActivityReport` extension. The extension has privileged
/// access to real app names, icons, and usage durations from the OS.
///
/// On older iOS versions the card shows a list from the App Group store
/// (bundle IDs only, no real icons).
struct ScreenTimeAppUsageView: View {

    @ObservedObject private var manager = ScreenTimeManager.shared
    @StateObject private var viewModel = ScreenTimeAppUsageViewModel()

    var body: some View {
        if manager.authorizationStatus != .authorized {
            notAuthorizedCard
        } else if !hasSelection {
            noSelectionCard
        } else {
            content
        }
    }

    private var hasSelection: Bool {
        guard let selection = manager.activitySelection else { return false }
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    // MARK: - Main Content

    private var content: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                // Header row
                HStack {
                    Label("Apps Used Today", systemImage: "app.badge.fill")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    // "See All" navigation link to full detail view
                    NavigationLink {
                        ScreenTimeAppDetailView()
                    } label: {
                        HStack(spacing: 3) {
                            Text("See All")
                                .font(AppTypography.captionSemibold)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)

                Divider()

                // Per-app usage content
                if #available(iOS 16.4, *) {
                    systemReportContent
                } else {
                    fallbackContent
                }
            }
        }
        .task { viewModel.loadData() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            viewModel.loadData()
        }
    }

    // MARK: - System Report (iOS 16.4+)

    @available(iOS 16.4, *)
    private var systemReportContent: some View {
        VStack(spacing: 0) {
            DeviceActivityReport(
                .init("com.flomks.sinura.usageReport"),
                filter: DeviceActivityFilter(
                    segment: .daily(
                        during: Calendar.current.dateInterval(of: .day, for: Date())
                            ?? DateInterval(start: Date(), duration: 86400)
                    ),
                    users: .all,
                    devices: .init([.iPhone, .iPad]),
                    applications: manager.activitySelection?.applicationTokens ?? [],
                    categories: manager.activitySelection?.categoryTokens ?? [],
                    webDomains: manager.activitySelection?.webDomainTokens ?? []
                )
            )
            .frame(
                minHeight: CGFloat(
                    max(3, (manager.activitySelection?.applicationTokens.count ?? 0)
                        + (manager.activitySelection?.categoryTokens.count ?? 0))
                ) * 52,
                maxHeight: 520
            )

            Divider()
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.success)
                Text("Live data from iOS Screen Time")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                NavigationLink {
                    ScreenTimeAppDetailView()
                } label: {
                    Text("Full Overview")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
        }
    }

    // MARK: - Fallback Content (pre-iOS 16.4)

    private var fallbackContent: some View {
        VStack(spacing: 0) {
            if viewModel.perAppUsage.isEmpty {
                emptyState
            } else {
                // Show top 5 apps
                let topApps = Array(viewModel.perAppUsage.prefix(5))
                let maxSeconds = topApps.first?.seconds ?? 1

                VStack(spacing: 0) {
                    ForEach(Array(topApps.enumerated()), id: \.element.id) { index, record in
                        if index > 0 {
                            Divider().padding(.leading, 48)
                        }
                        fallbackRow(record, maxSeconds: maxSeconds)
                    }
                }

                if viewModel.perAppUsage.count > 5 {
                    Divider()
                    NavigationLink {
                        ScreenTimeAppDetailView()
                    } label: {
                        HStack {
                            Text("Show \(viewModel.perAppUsage.count - 5) more apps")
                                .font(AppTypography.captionSemibold)
                                .foregroundStyle(AppColors.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppColors.primary)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func fallbackRow(_ record: PerAppUsageRecord, maxSeconds: Int) -> some View {
        HStack(spacing: AppSpacing.sm) {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.backgroundTertiary)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "app.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textTertiary)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName(for: record.bundleID))
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                if !record.categoryToken.isEmpty {
                    Text(record.categoryToken)
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textSecondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.backgroundTertiary)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(seconds: record.seconds, maxSeconds: maxSeconds))
                            .frame(
                                width: geo.size.width * CGFloat(record.seconds) / CGFloat(max(1, maxSeconds)),
                                height: 4
                            )
                    }
                }
                .frame(height: 4)
            }

            Spacer()

            Text(formatSeconds(record.seconds))
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, AppSpacing.xs)
        .padding(.horizontal, AppSpacing.md)
    }

    private var emptyState: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: AppSpacing.iconSizeSmall))
                .foregroundStyle(AppColors.info)
            VStack(alignment: .leading, spacing: 2) {
                Text("No app usage data yet today")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                Text("Data appears once you start using the tracked apps.")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Not Authorized / No Selection

    private var notAuthorizedCard: some View {
        Card {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "xmark.shield.fill")
                    .font(.system(size: AppSpacing.iconSizeStandard))
                    .foregroundStyle(AppColors.textTertiary)
                Text("Enable Screen Time to see per-app usage.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
        }
    }

    private var noSelectionCard: some View {
        Card {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "app.badge.fill")
                    .font(.system(size: AppSpacing.iconSizeStandard))
                    .foregroundStyle(AppColors.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No apps selected for tracking")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                    NavigationLink {
                        ScreenTimeSettingsView()
                    } label: {
                        Text("Select apps in Screen Time Settings")
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private func displayName(for bundleID: String) -> String {
        let parts = bundleID.split(separator: ".")
        let last = parts.last.map(String.init) ?? bundleID
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    private func barColor(seconds: Int, maxSeconds: Int) -> Color {
        let fraction = Double(seconds) / Double(max(1, maxSeconds))
        if fraction >= 0.7 { return AppColors.error }
        if fraction >= 0.4 { return AppColors.warning }
        return AppColors.primary
    }

    private func formatSeconds(_ seconds: Int) -> String {
        if seconds <= 0 { return "0m" }
        if seconds < 60 { return "\(seconds)s" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - ScreenTimeAppUsageViewModel

@MainActor
final class ScreenTimeAppUsageViewModel: ObservableObject {

    @Published private(set) var perAppUsage: [PerAppUsageRecord] = []
    @Published private(set) var isLoading: Bool = false

    private let store = ScreenTimeUsageStore.shared

    func loadData() {
        isLoading = true
        perAppUsage = store.todayPerAppUsage()
        isLoading = false
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ScreenTimeAppUsageView") {
    NavigationStack {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                ScreenTimeAppUsageView()
            }
            .padding(AppSpacing.md)
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle("App Usage")
    }
}
#endif
