import SwiftUI
import Charts

// MARK: - ScreenTimeStatsInlineView

/// Inline version of the Screen Time statistics, embedded in the Stats tab.
///
/// Unlike `ScreenTimeStatsView` (which is a full navigation destination),
/// this view is designed to be placed inside a `LazyVStack` within the
/// Stats tab's `ScrollView`. It does not have its own navigation bar.
///
/// Shows:
/// - Usage summary card with OS-tracked system usage (reinstall-proof)
/// - Per-app usage breakdown for today
/// - Daily usage chart
/// - Day-by-day list
struct ScreenTimeStatsInlineView: View {

    @StateObject private var viewModel = ScreenTimeStatsViewModel()
    @ObservedObject private var manager = ScreenTimeManager.shared

    var body: some View {
        if manager.authorizationStatus != .authorized {
            screenTimeNotSetupCard
        } else {
            screenTimeContent
        }
    }

    // MARK: - Not Set Up Card

    private var screenTimeNotSetupCard: some View {
        Card {
            VStack(spacing: AppSpacing.md) {
                Image(icon: .hourglassFill)
                    .font(.system(size: AppSpacing.iconSizeXL, weight: .light))
                    .foregroundStyle(AppColors.textTertiary)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: AppSpacing.xs) {
                    Text("Screen Time Not Set Up")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Enable Screen Time in Settings to see your app usage statistics here.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                NavigationLink {
                    ScreenTimeSettingsView()
                } label: {
                    Text("Set Up Screen Time")
                        .font(AppTypography.buttonPrimary)
                        .foregroundStyle(AppColors.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppSpacing.buttonHeightSecondary)
                        .background(AppColors.primary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, AppSpacing.lg)
            .frame(maxWidth: .infinity)
        }
        .task { viewModel.loadData() }
    }

    // MARK: - Screen Time Content

    private var screenTimeContent: some View {
        VStack(spacing: AppSpacing.md) {
            // Period picker
            Picker("Period", selection: $viewModel.selectedPeriod) {
                ForEach(ScreenTimePeriod.allCases) { period in
                    Text(period.label).tag(period)
                }
            }
            .pickerStyle(.segmented)

            // Summary card
            screenTimeSummaryCard

            // Per-app usage (today only)
            if viewModel.selectedPeriod == .today {
                ScreenTimeAppUsageView()
            }

            // Chart
            if !viewModel.chartData.isEmpty {
                screenTimeChart
            }

            // Day list
            if !viewModel.records.isEmpty {
                screenTimeDayList
            } else if viewModel.selectedPeriod != .today {
                noDataCard
            }
        }
        .task { viewModel.loadData() }
    }

    // MARK: - Summary Card

    private var screenTimeSummaryCard: some View {
        Card {
            VStack(spacing: AppSpacing.md) {
                HStack {
                    Label("App Usage", icon: .hourglassFill)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    // Blocking status badge
                    if manager.isBlocking {
                        Text("Blocking Active")
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.textOnPrimary)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 3)
                            .background(AppColors.error, in: Capsule())
                    }
                }

                HStack(spacing: AppSpacing.md) {
                    inlineMetric(
                        value: formatSeconds(viewModel.displayUsedSeconds),
                        label: "Total Used",
                        color: usageColor
                    )
                    Divider().frame(height: 40)
                    inlineMetric(
                        value: formatSeconds(viewModel.dailyAverageSeconds),
                        label: "Daily Avg",
                        color: AppColors.info
                    )
                    Divider().frame(height: 40)
                    inlineMetric(
                        value: "\(viewModel.totalShieldTriggers)",
                        label: "Blocked",
                        color: viewModel.totalShieldTriggers > 0 ? AppColors.error : AppColors.success
                    )
                }

                // System usage badge (reinstall-proof indicator)
                if viewModel.selectedPeriod == .today && viewModel.todaySystemUsageSeconds > 0 {
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColors.success)
                        Text("iOS Screen Time tracking active")
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                    }
                }
            }
        }
    }

    private func inlineMetric(value: String, label: String, color: Color) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Text(value)
                .font(AppTypography.bodySemibold)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chart

    @ViewBuilder
    private var screenTimeChart: some View {
        if #available(iOS 16.0, *) {
            Card {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Daily Usage (minutes)")
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
                    .frame(height: 140)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let m = value.as(Int.self) {
                                    Text("\(m)")
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

                    HStack(spacing: AppSpacing.md) {
                        legendDot(color: AppColors.primary, label: "Normal")
                        legendDot(color: AppColors.error, label: "Credit exhausted")
                    }
                }
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Day List

    private var screenTimeDayList: some View {
        Card(hasShadow: false) {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.records.prefix(7).enumerated()), id: \.element.id) { index, record in
                    if index > 0 { Divider() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortDate(record.date))
                                .font(AppTypography.bodySemibold)
                                .foregroundStyle(AppColors.textPrimary)
                            if record.creditExhausted {
                                Text("Credit exhausted")
                                    .font(AppTypography.caption2)
                                    .foregroundStyle(AppColors.error)
                            }
                        }
                        Spacer()
                        Text(formatSeconds(record.totalSeconds))
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(AppColors.textPrimary)
                            .monospacedDigit()
                        Image(icon: record.creditExhausted ? .xmarkShieldFill : .checkmarkShieldFill)
                            .font(.system(size: AppSpacing.iconSizeSmall))
                            .foregroundStyle(record.creditExhausted ? AppColors.error : AppColors.success)
                    }
                    .padding(.vertical, AppSpacing.xs)
                }
            }
            .padding(.horizontal, AppSpacing.sm)
        }
    }

    private var noDataCard: some View {
        Card(hasShadow: false) {
            HStack(spacing: AppSpacing.sm) {
                Image(icon: .infoCircle)
                    .font(.system(size: AppSpacing.iconSizeSmall))
                    .foregroundStyle(AppColors.info)
                Text("No usage data for this period yet.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private var usageColor: Color {
        let fraction = viewModel.usageFraction
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

    private func shortDate(_ isoDate: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        let display = DateFormatter()
        display.dateFormat = "EEE, MMM d"
        return display.string(from: date)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ScreenTimeStatsInlineView") {
    NavigationStack {
        ScrollView {
            LazyVStack(spacing: AppSpacing.md) {
                ScreenTimeStatsInlineView()
            }
            .padding(AppSpacing.md)
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle("Stats")
    }
}
#endif
