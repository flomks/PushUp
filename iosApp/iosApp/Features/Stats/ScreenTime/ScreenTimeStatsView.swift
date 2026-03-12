import SwiftUI
import Charts

// MARK: - ScreenTimeStatsView

/// In-app Screen Time statistics screen.
///
/// Shows how much time was spent in the tracked apps, broken down by day,
/// and compares it against earned time credit.
///
/// **Layout**
/// ```
/// +-----------------------------------+
/// |  Screen Time Stats                |
/// |  [Today | Week | Month]           |  <- segmented picker
/// |                                   |
/// |  [Usage Summary Card]             |  <- total used vs. earned
/// |  [Per-App Usage Today]            |  <- per-app breakdown (new)
/// |  [Bar Chart -- daily usage]       |
/// |  [Day-by-day list]                |
/// |                                   |
/// +-----------------------------------+
/// ```
///
/// **Data sources:**
/// - `ScreenTimeUsageStore` (App Group UserDefaults) for daily records.
/// - `DeviceActivityReport` extension for live per-app usage (iOS 16.4+).
struct ScreenTimeStatsView: View {

    @StateObject private var viewModel = ScreenTimeStatsViewModel()
    @ObservedObject private var manager = ScreenTimeManager.shared

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()

            if manager.authorizationStatus != .authorized {
                notAuthorizedView
            } else if viewModel.records.isEmpty && viewModel.todaySystemUsageSeconds == 0 {
                emptyStateView
            } else {
                mainContent
            }
        }
        .navigationTitle("Screen Time")
        .navigationBarTitleDisplayMode(.large)
        .task { viewModel.loadData() }
        .refreshable { viewModel.loadData() }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.md) {
                periodPicker
                summaryCard

                // Per-app usage section (always shown for "Today" period)
                if viewModel.selectedPeriod == .today {
                    ScreenTimeAppUsageView()
                }

                if !viewModel.chartData.isEmpty {
                    usageChart
                }

                if !viewModel.records.isEmpty {
                    dayList
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.screenVerticalBottom)
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Picker("Period", selection: $viewModel.selectedPeriod) {
            ForEach(ScreenTimePeriod.allCases) { period in
                Text(period.label).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        Card {
            VStack(spacing: AppSpacing.md) {
                HStack {
                    Label("Usage Summary", icon: .hourglassFill)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text(viewModel.selectedPeriod.label)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack(spacing: AppSpacing.md) {
                    // Time used (prefer system usage for today)
                    summaryMetric(
                        value: formatSeconds(viewModel.displayUsedSeconds),
                        label: "Time Used",
                        icon: .hourglassBottomHalf,
                        color: usageColor
                    )

                    Divider().frame(height: 48)

                    // Shield triggers
                    summaryMetric(
                        value: "\(viewModel.totalShieldTriggers)",
                        label: "Blocked",
                        icon: .lockApp,
                        color: viewModel.totalShieldTriggers > 0 ? AppColors.error : AppColors.success
                    )

                    Divider().frame(height: 48)

                    // Days tracked
                    summaryMetric(
                        value: "\(viewModel.records.count)",
                        label: "Days Tracked",
                        icon: .calendarBadgeCheckmark,
                        color: AppColors.info
                    )
                }

                // Usage progress bar
                if viewModel.displayUsedSeconds > 0 {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        HStack {
                            Text("Daily Average")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Text(formatSeconds(viewModel.dailyAverageSeconds))
                                .font(AppTypography.captionSemibold)
                                .foregroundStyle(AppColors.textPrimary)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(AppColors.backgroundTertiary)
                                    .frame(height: 8)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [usageColor, usageColor.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(
                                        width: geo.size.width * viewModel.usageFraction,
                                        height: 8
                                    )
                                    .animation(.easeInOut(duration: 0.5), value: viewModel.usageFraction)
                            }
                        }
                        .frame(height: 8)
                    }
                }

                // System usage indicator (shows when OS-tracked data is available)
                if viewModel.selectedPeriod == .today && viewModel.todaySystemUsageSeconds > 0 {
                    systemUsageIndicator
                }
            }
        }
    }

    /// Shows a badge indicating the usage value comes from the OS (reinstall-proof).
    private var systemUsageIndicator: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.success)
            Text("Usage tracked by iOS Screen Time -- reinstall-proof")
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xxs)
        .background(AppColors.success.opacity(0.06), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip))
    }

    private func summaryMetric(value: String, label: String, icon: AppIcon, color: Color) -> some View {
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

    // MARK: - Usage Chart

    @ViewBuilder
    private var usageChart: some View {
        if #available(iOS 16.0, *) {
            Card {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Daily Usage")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Chart(viewModel.chartData) { item in
                        BarMark(
                            x: .value("Date", item.shortLabel),
                            y: .value("Minutes", item.minutes)
                        )
                        .foregroundStyle(
                            item.creditExhausted
                                ? AppColors.error.gradient
                                : AppColors.primary.gradient
                        )
                        .cornerRadius(4)
                    }
                    .frame(height: 160)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let minutes = value.as(Int.self) {
                                    Text("\(minutes)m")
                                        .font(AppTypography.caption2)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(AppColors.separator.opacity(0.5))
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let label = value.as(String.self) {
                                    Text(label)
                                        .font(AppTypography.caption2)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                        }
                    }

                    // Legend
                    HStack(spacing: AppSpacing.md) {
                        legendItem(color: AppColors.primary, label: "Normal usage")
                        legendItem(color: AppColors.error, label: "Credit exhausted")
                    }
                }
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 8)
            Text(label)
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Day List

    private var dayList: some View {
        Card(hasShadow: false) {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        Divider()
                            .padding(.leading, AppSpacing.md + AppSpacing.sm)
                    }
                    dayRow(record: record)
                }
            }
        }
    }

    private func dayRow(record: AppUsageRecord) -> some View {
        HStack(spacing: AppSpacing.sm) {
            // Date
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(record.date))
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                Text(relativeDate(record.date))
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            // Usage time
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatSeconds(record.totalSeconds))
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .monospacedDigit()

                if record.creditExhausted {
                    Text("Credit exhausted")
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.error)
                } else if record.shieldTriggerCount > 0 {
                    Text("Blocked \(record.shieldTriggerCount)x")
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.warning)
                }
            }

            // Status icon
            Image(icon: record.creditExhausted ? .xmarkShieldFill : .checkmarkShieldFill)
                .font(.system(size: AppSpacing.iconSizeSmall))
                .foregroundStyle(record.creditExhausted ? AppColors.error : AppColors.success)
        }
        .padding(.vertical, AppSpacing.xs)
        .padding(.horizontal, AppSpacing.md)
    }

    // MARK: - Empty / Not Authorized States

    private var notAuthorizedView: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(icon: .hourglassFill)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(AppColors.textTertiary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: AppSpacing.xs) {
                Text("Screen Time Not Set Up")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Enable Screen Time in Settings to track your app usage and block distracting apps.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }
        }
        .padding(AppSpacing.xl)
    }

    private var emptyStateView: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(icon: .chartLineUptrendXYAxis)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(AppColors.textTertiary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: AppSpacing.xs) {
                Text("No Usage Data Yet")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Usage data will appear here once you start using the apps you've selected for tracking.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            // Show per-app view even in empty state so user can see live data
            ScreenTimeAppUsageView()
                .padding(.horizontal, AppSpacing.screenHorizontal)
        }
        .padding(AppSpacing.xl)
    }

    // MARK: - Helpers

    private var usageColor: Color {
        let fraction = viewModel.usageFraction
        if fraction >= 1.0 { return AppColors.error }
        if fraction >= 0.8 { return AppColors.warning }
        return AppColors.primary
    }

    private func formatSeconds(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func formatDate(_ isoDate: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .none
        return display.string(from: date)
    }

    private func relativeDate(_ isoDate: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: isoDate) else { return "" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - ScreenTimePeriod

enum ScreenTimePeriod: String, CaseIterable, Identifiable {
    case today  = "today"
    case week   = "week"
    case month  = "month"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .week:  return "Week"
        case .month: return "Month"
        }
    }

    var days: Int {
        switch self {
        case .today: return 1
        case .week:  return 7
        case .month: return 30
        }
    }
}

// MARK: - ScreenTimeChartItem

struct ScreenTimeChartItem: Identifiable {
    let id: String
    let shortLabel: String
    let minutes: Int
    let creditExhausted: Bool
}

// MARK: - ScreenTimeStatsViewModel

@MainActor
final class ScreenTimeStatsViewModel: ObservableObject {

    @Published var selectedPeriod: ScreenTimePeriod = .week {
        didSet { loadData() }
    }

    @Published private(set) var records: [AppUsageRecord] = []
    @Published private(set) var chartData: [ScreenTimeChartItem] = []
    @Published private(set) var todaySystemUsageSeconds: Int = 0

    private let store = ScreenTimeUsageStore.shared

    // MARK: - Computed

    var totalUsedSeconds: Int {
        records.reduce(0) { $0 + $1.totalSeconds }
    }

    /// The usage value to display in the summary card.
    /// For "Today", prefers the OS-tracked system usage (reinstall-proof).
    var displayUsedSeconds: Int {
        if selectedPeriod == .today && todaySystemUsageSeconds > 0 {
            return todaySystemUsageSeconds
        }
        return totalUsedSeconds
    }

    var totalShieldTriggers: Int {
        records.reduce(0) { $0 + $1.shieldTriggerCount }
    }

    var dailyAverageSeconds: Int {
        guard !records.isEmpty else { return 0 }
        return totalUsedSeconds / records.count
    }

    /// Fraction of a "reasonable" daily limit (2 hours = 7200s) used on average.
    var usageFraction: CGFloat {
        let reasonableDaily = 7200.0
        let seconds = selectedPeriod == .today
            ? Double(displayUsedSeconds)
            : Double(dailyAverageSeconds)
        return min(1.0, seconds / reasonableDaily)
    }

    // MARK: - Load

    func loadData() {
        let raw = selectedPeriod == .today
            ? (store.todayRecord().map { [$0] } ?? [])
            : store.records(forLastDays: selectedPeriod.days)

        records = raw

        // Load the OS-tracked system usage for today.
        todaySystemUsageSeconds = store.todaySystemUsageSeconds

        // Build chart data
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let shortFormatter = DateFormatter()
        shortFormatter.dateFormat = "d/M"

        chartData = raw.reversed().map { record in
            let date = dateFormatter.date(from: record.date) ?? Date()
            return ScreenTimeChartItem(
                id: record.date,
                shortLabel: shortFormatter.string(from: date),
                minutes: record.totalSeconds / 60,
                creditExhausted: record.creditExhausted
            )
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ScreenTimeStatsView") {
    NavigationStack {
        ScreenTimeStatsView()
    }
}

#Preview("ScreenTimeStatsView - Dark") {
    NavigationStack {
        ScreenTimeStatsView()
    }
    .preferredColorScheme(.dark)
}
#endif
