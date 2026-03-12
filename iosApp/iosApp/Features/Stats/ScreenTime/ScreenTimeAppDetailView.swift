import SwiftUI
import DeviceActivity
import FamilyControls

// MARK: - ScreenTimeAppDetailView

/// Full-screen overview of per-app usage for today.
///
/// This is the primary "how long did I use each app today?" screen.
/// It uses the DeviceActivityReport framework (iOS 16.4+) to display
/// real app names, icons, and usage durations directly from the OS.
///
/// **Layout**
/// ```
/// +-----------------------------------+
/// |  App Usage Today     [date]       |
/// |                                   |
/// |  [Summary Header]                 |  <- total used, credit left, status
/// |  [Credit Progress Bar]            |
/// |                                   |
/// |  [Per-App List via DeviceActivity]|  <- real names + icons from OS
/// |                                   |
/// +-----------------------------------+
/// ```
///
/// **Data source:** `DeviceActivityReport` extension (iOS 16.4+).
/// The extension renders the per-app list with real app names and icons.
/// On older iOS versions, falls back to the App Group store data.
struct ScreenTimeAppDetailView: View {

    @ObservedObject private var manager = ScreenTimeManager.shared
    @StateObject private var viewModel = ScreenTimeAppDetailViewModel()

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()

            if manager.authorizationStatus != .authorized {
                notAuthorizedView
            } else if !hasSelection {
                noSelectionView
            } else {
                mainContent
            }
        }
        .navigationTitle("App Usage Today")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Text(todayDateLabel)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .task { viewModel.loadData() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            viewModel.loadData()
        }
    }

    private var hasSelection: Bool {
        guard let selection = manager.activitySelection else { return false }
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    private var todayDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.md) {
                summaryHeader
                creditProgressCard
                appUsageSection
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.screenVerticalBottom)
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        Card(padding: AppSpacing.md) {
            VStack(spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.md) {
                    summaryMetric(
                        icon: "hourglass.bottomhalf.filled",
                        value: formatSeconds(viewModel.totalUsedSeconds),
                        label: "Used Today",
                        color: usageColor
                    )

                    Divider().frame(height: 44)

                    summaryMetric(
                        icon: "hourglass",
                        value: formatSeconds(max(0, viewModel.availableSeconds)),
                        label: "Credit Left",
                        color: creditColor
                    )

                    Divider().frame(height: 44)

                    summaryMetric(
                        icon: manager.isBlocking ? "lock.app.dashed" : "checkmark.shield",
                        value: manager.isBlocking ? "Blocked" : "Open",
                        label: "App Access",
                        color: manager.isBlocking ? AppColors.error : AppColors.success
                    )
                }

                // Blocking banner
                if manager.isBlocking {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "lock.app.dashed")
                            .font(.system(size: 12, weight: .semibold))
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

                // System tracking badge
                if viewModel.isSystemTracked {
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColors.success)
                        Text("Tracked by iOS Screen Time -- reinstall-proof")
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                    }
                }
            }
        }
    }

    private func summaryMetric(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(AppTypography.bodySemibold)
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Credit Progress Card

    private var creditProgressCard: some View {
        Card(padding: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Text("Daily Credit Usage")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("\(Int(viewModel.usageFraction * 100))% used")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(usageColor)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppColors.backgroundTertiary)
                            .frame(height: 12)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: progressGradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: geo.size.width * viewModel.usageFraction,
                                height: 12
                            )
                            .animation(.spring(duration: 0.6, bounce: 0.1), value: viewModel.usageFraction)
                    }
                }
                .frame(height: 12)

                HStack {
                    Text("0")
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer()
                    Text(formatSeconds(viewModel.totalCreditSeconds))
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }

    // MARK: - App Usage Section

    @ViewBuilder
    private var appUsageSection: some View {
        if #available(iOS 16.4, *) {
            // Primary: system DeviceActivityReport with real app names + icons
            systemReportCard
        } else {
            // Fallback: App Group store data (bundle IDs only)
            fallbackAppListCard
        }
    }

    // MARK: - System Report Card (iOS 16.4+)

    @available(iOS 16.4, *)
    private var systemReportCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                // Section header
                HStack {
                    Label("Apps Used Today", systemImage: "app.badge.fill")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("Live")
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.success)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 3)
                        .background(AppColors.success.opacity(0.12), in: Capsule())
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)

                Divider()

                // The DeviceActivityReport view is rendered by our extension.
                // It shows real app names, icons, and usage durations from the OS.
                // The filter restricts it to today's data for the selected apps.
                DeviceActivityReport(
                    .init("com.flomks.pushup.usageReport"),
                    filter: DeviceActivityFilter(
                        segment: .daily(
                            during: Calendar.current.dateInterval(of: .day, for: Date())
                                ?? DateInterval(start: Date(), duration: 86400)
                        ),
                        users: .all,
                        devices: .init([.iPhone, .iPad])
                    )
                )
                // Let the content determine its own height
                .frame(minHeight: 120)

                // Footer note
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                    Text("Usage data is provided by iOS Screen Time and updates in real time.")
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
            }
        }
    }

    // MARK: - Fallback App List (pre-iOS 16.4 or no extension data)

    private var fallbackAppListCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Label("Apps Used Today", systemImage: "app.badge.fill")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                }

                if viewModel.perAppUsage.isEmpty {
                    emptyAppsState
                } else {
                    fallbackAppList
                }
            }
        }
    }

    private var fallbackAppList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.perAppUsage.enumerated()), id: \.element.id) { index, record in
                if index > 0 {
                    Divider().padding(.leading, 48)
                }
                fallbackAppRow(record)
            }
        }
    }

    private func fallbackAppRow(_ record: PerAppUsageRecord) -> some View {
        HStack(spacing: AppSpacing.sm) {
            // Generic app icon (no real icon available without extension)
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

                // Usage bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.backgroundTertiary)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(seconds: record.seconds))
                            .frame(
                                width: geo.size.width * barFraction(seconds: record.seconds),
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

    private var emptyAppsState: some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: "app.badge")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(AppColors.textTertiary)
                .symbolRenderingMode(.hierarchical)

            Text("No app usage data yet today.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            Text("Data appears once you start using the tracked apps.")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
    }

    // MARK: - Not Authorized / No Selection

    private var notAuthorizedView: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "xmark.shield.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(AppColors.textTertiary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: AppSpacing.xs) {
                Text("Screen Time Not Enabled")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Enable Screen Time in Settings to see per-app usage data.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            NavigationLink {
                ScreenTimeSettingsView()
            } label: {
                Text("Open Screen Time Settings")
                    .font(AppTypography.buttonPrimary)
                    .foregroundStyle(AppColors.textOnPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppSpacing.buttonHeightPrimary)
                    .background(AppColors.primary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.xl)
        }
        .padding(AppSpacing.xl)
    }

    private var noSelectionView: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "app.badge.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(AppColors.textTertiary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: AppSpacing.xs) {
                Text("No Apps Selected")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Select apps to track in Screen Time Settings to see usage data here.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            NavigationLink {
                ScreenTimeSettingsView()
            } label: {
                Text("Select Apps to Track")
                    .font(AppTypography.buttonPrimary)
                    .foregroundStyle(AppColors.textOnPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppSpacing.buttonHeightPrimary)
                    .background(AppColors.primary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.xl)
        }
        .padding(AppSpacing.xl)
    }

    // MARK: - Helpers

    private var usageColor: Color {
        let f = viewModel.usageFraction
        if f >= 1.0 { return AppColors.error }
        if f >= 0.7 { return AppColors.warning }
        return AppColors.primary
    }

    private var creditColor: Color {
        let available = viewModel.availableSeconds
        if available <= 0 { return AppColors.error }
        if available < 300 { return AppColors.warning }
        return AppColors.success
    }

    private var progressGradientColors: [Color] {
        let f = viewModel.usageFraction
        if f >= 1.0 { return [AppColors.error, AppColors.error] }
        if f >= 0.7 { return [AppColors.primary, AppColors.warning] }
        return [AppColors.primary, AppColors.secondary]
    }

    private func barFraction(seconds: Int) -> CGFloat {
        let total = viewModel.perAppUsage.first?.seconds ?? 1
        return min(1.0, CGFloat(seconds) / CGFloat(max(1, total)))
    }

    private func barColor(seconds: Int) -> Color {
        let total = viewModel.perAppUsage.first?.seconds ?? 1
        let fraction = Double(seconds) / Double(max(1, total))
        if fraction >= 0.7 { return AppColors.error }
        if fraction >= 0.4 { return AppColors.warning }
        return AppColors.primary
    }

    private func displayName(for bundleID: String) -> String {
        let parts = bundleID.split(separator: ".")
        let last = parts.last.map(String.init) ?? bundleID
        return last.prefix(1).uppercased() + last.dropFirst()
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

// MARK: - ScreenTimeAppDetailViewModel

@MainActor
final class ScreenTimeAppDetailViewModel: ObservableObject {

    @Published private(set) var perAppUsage: [PerAppUsageRecord] = []
    @Published private(set) var totalUsedSeconds: Int = 0
    @Published private(set) var availableSeconds: Int = 0
    @Published private(set) var totalCreditSeconds: Int = 0
    @Published private(set) var isSystemTracked: Bool = false

    private let store = ScreenTimeUsageStore.shared
    private let sharedDefaults = UserDefaults(suiteName: ScreenTimeConstants.appGroupID)

    var usageFraction: CGFloat {
        guard totalCreditSeconds > 0 else { return 0 }
        return min(1.0, CGFloat(totalUsedSeconds) / CGFloat(totalCreditSeconds))
    }

    func loadData() {
        // Per-app usage from App Group (written by DeviceActivityReport extension)
        perAppUsage = store.todayPerAppUsage()

        // Total usage: prefer OS-tracked system value
        let systemUsage = store.todaySystemUsageSeconds
        isSystemTracked = systemUsage > 0
        totalUsedSeconds = systemUsage > 0 ? systemUsage : (store.todayRecord()?.totalSeconds ?? 0)

        // Credit values from App Group
        availableSeconds = sharedDefaults?.integer(forKey: ScreenTimeConstants.Keys.availableSeconds) ?? 0
        let startOfDay = sharedDefaults?.integer(forKey: ScreenTimeConstants.Keys.startOfDaySeconds) ?? 0
        totalCreditSeconds = startOfDay > 0 ? startOfDay : (availableSeconds + totalUsedSeconds)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ScreenTimeAppDetailView") {
    NavigationStack {
        ScreenTimeAppDetailView()
    }
}

#Preview("ScreenTimeAppDetailView - Dark") {
    NavigationStack {
        ScreenTimeAppDetailView()
    }
    .preferredColorScheme(.dark)
}
#endif
