import SwiftUI
import DeviceActivity
import FamilyControls

// MARK: - ScreenTimeAppUsageView

/// Displays per-app usage for today using the DeviceActivityReport framework.
///
/// This view embeds a `DeviceActivityReport` which is rendered by the
/// `DeviceActivityReport` extension in a system-provided container.
/// The extension has access to the actual per-app usage data from the OS.
///
/// **iOS 16.4+ required** for `DeviceActivityReport`.
///
/// Falls back to a simple list from the App Group store on older iOS versions
/// or when the extension has not yet written data.
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
        VStack(spacing: AppSpacing.md) {
            // System DeviceActivityReport (iOS 16.4+)
            if #available(iOS 16.4, *) {
                systemReportCard
            }

            // Per-app usage list from App Group store
            perAppUsageCard
        }
        .task { viewModel.loadData() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            viewModel.loadData()
        }
    }

    // MARK: - System Report Card (iOS 16.4+)

    @available(iOS 16.4, *)
    private var systemReportCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Label("Today's App Usage", icon: .hourglassFill)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("Live")
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.success)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 3)
                        .background(AppColors.success.opacity(0.1), in: Capsule())
                }

                // Embed the system DeviceActivityReport view.
                // This is rendered by our DeviceActivityReport extension and
                // shows the actual per-app usage data from the OS.
                DeviceActivityReport(
                    .init("com.flomks.pushup.usageReport"),
                    filter: DeviceActivityFilter(
                        segment: .daily(
                            during: Calendar.current.dateInterval(of: .day, for: Date()) ?? DateInterval()
                        ),
                        users: .all,
                        devices: .init([.iPhone, .iPad])
                    )
                )
                .frame(minHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            }
        }
    }

    // MARK: - Per-App Usage List (from App Group store)

    private var perAppUsageCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Label("Tracked Apps Today", icon: .appBadgeFill)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                    }
                }

                if viewModel.perAppUsage.isEmpty {
                    emptyPerAppState
                } else {
                    perAppList
                }
            }
        }
    }

    private var perAppList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.perAppUsage.enumerated()), id: \.element.id) { index, record in
                if index > 0 {
                    Divider()
                        .padding(.leading, AppSpacing.md)
                }
                perAppRow(record: record, maxSeconds: viewModel.perAppUsage.first?.seconds ?? 1)
            }
        }
    }

    private func perAppRow(_ record: PerAppUsageRecord, maxSeconds: Int) -> some View {
        HStack(spacing: AppSpacing.sm) {
            // App icon placeholder (bundle ID based)
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.backgroundTertiary)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "app.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textTertiary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: record.bundleID))
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                if !record.categoryToken.isEmpty {
                    Text(record.categoryToken)
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textSecondary)
                }

                // Usage bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.backgroundTertiary)
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(usageBarColor(seconds: record.seconds))
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
    }

    private var emptyPerAppState: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(icon: .infoCircle)
                .font(.system(size: AppSpacing.iconSizeSmall))
                .foregroundStyle(AppColors.info)
            VStack(alignment: .leading, spacing: 2) {
                Text("No per-app data yet")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                Text("Data appears after the first usage threshold is reached.")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: - Not Authorized / No Selection

    private var notAuthorizedCard: some View {
        Card {
            HStack(spacing: AppSpacing.sm) {
                Image(icon: .xmarkShieldFill)
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
                Image(icon: .appBadgeFill)
                    .font(.system(size: AppSpacing.iconSizeStandard))
                    .foregroundStyle(AppColors.textTertiary)
                Text("Select apps to track in Screen Time Settings.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private func displayName(for bundleID: String) -> String {
        // Extract a readable name from the bundle ID.
        // e.g. "com.apple.mobilesafari" -> "mobilesafari" -> "Mobilesafari"
        // In production, you'd use LSApplicationWorkspace or a lookup table.
        let parts = bundleID.split(separator: ".")
        let last = parts.last.map(String.init) ?? bundleID
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    private func usageBarColor(seconds: Int) -> Color {
        let fraction = Double(seconds) / 7200.0  // 2 hours = "full"
        if fraction >= 1.0 { return AppColors.error }
        if fraction >= 0.6 { return AppColors.warning }
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
